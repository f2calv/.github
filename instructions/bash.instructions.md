---
description: 'Bash scripting conventions for structure, error handling, logging, testability and style.'
applyTo: '**/*.sh'
---

# Bash

## Structure

- **Shebang**: Use `#!/usr/bin/env bash`, which resolves Bash through `PATH` instead of assuming it is installed at `/bin/bash`.
- **Header comment**: Open every script with a short comment block stating what it does. A script invoked from a GitHub Actions composite step must also carry a `# Required environment variables: X, Y, Z` line and note which are optional. The header is the script's contract, so a reader never needs to open the calling `action.yml` to discover what it needs.
- **Location**: Place non-trivial or composite-action scripts in a dot-prefixed `.scripts/` folder at the repository or action root.
- **Executable bit**: Set `chmod +x` on any script invoked directly by path rather than through `bash script.sh`. Verify the tracked mode with `git ls-files -s path/to/script.sh`, which must report `100755`; if it reports `100644`, correct it with `git update-index --chmod=+x path/to/script.sh` before committing. Where `git config core.fileMode` is `false`, staging does not pick up a `chmod +x` applied before `git add`, so this check is mandatory.
- **Manual runbooks**: A script intended to be read and executed step by step by a human, containing interactive or destructive commands such as `sudo reboot` or an editor invocation, is exempt from the automation conventions below. Say so in the header, for example `# Run manually, step by step — not intended for unattended execution.`, so it is not mistaken for broken automation.

## Error Handling

- Validate required environment variables **before** enabling strict mode, so a missing value produces one clear, intentional error instead of Bash's raw unbound-variable trace:

  ```bash
  # Validate required environment variables before enabling strict mode
  for var in FOO BAR BAZ; do
    if [[ -z "${!var:-}" ]]; then
      echo "::error::Required environment variable $var is not set."
      exit 1
    fi
  done

  set -euo pipefail
  ```

- Require `set -euo pipefail` in every automation script — exit on error, exit on unset variable, and fail a pipeline on any stage's non-zero exit — placed immediately after the required-variable validation loop.
- Default optional variables explicitly before `set -u` takes effect, using `: "${VAR:=}"` or a per-use `"${VAR:-}"`, so referencing a legitimately unset optional variable does not abort the script.
- Quote every variable expansion (`"$var"`, `"${arr[@]}"`) unless word splitting or globbing is intentional. This includes file paths, which may contain spaces.
- Fail fast with a specific message rather than letting an empty or invalid value propagate into a downstream command's cryptic error. Validate credentials and inputs before the command that consumes them, not after it fails.

## Logging and GitHub Actions Annotations

- Use `::error::message` for failures, or `::error file=$FILE::message` when a specific file is implicated.
- Use `::warning title=X::message` for non-fatal issues.
- Use `::add-mask::$value` for any secret obtained or derived at runtime, such as an exchanged token or a short-lived API key, not only for secrets passed in as inputs.
- Log progress and diagnostics with `echo`, one `echo` per line. Prefer that over `printf` continuation chains, which are harder to read in raw logs.
- Never log a secret in full. Redact it, for example `echo "REGISTRY_PASSWORD=***"`, or register it with `::add-mask::`.

## Testability

- A script extracted from a composite action must be runnable and testable standalone, without a live Actions run. Depend only on its documented environment variables and nothing else implicit in the Actions runtime; `GITHUB_ENV` and `GITHUB_OUTPUT` may point at temporary local files.
- Mock external commands — HTTP clients, package managers, version-control and cloud CLIs — by placing stub executables earlier on `PATH` instead of calling real endpoints or requiring live credentials.
- Exercise the success path and every distinct error path, including a missing required variable and an empty or invalid response.
- Run `shellcheck` against new or modified scripts before committing and resolve every finding above informational severity. An informational finding on a deliberately single-quoted expression passed to a query tool is expected and may be left as-is.

## Style

- Declare every function-scoped variable with `local`.
- Lowercase values passed to case-sensitive systems that require lowercase, such as OCI registries and repositories, with `${var,,}`.
- Clean up every temporary file and directory the script creates, including artifacts created inside a loop, so one iteration's leftovers cannot leak into the next.
