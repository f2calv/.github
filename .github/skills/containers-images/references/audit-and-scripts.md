# Audit and Scripts

Parameters, rules and helper scripts for `Test-Dockerfile.ps1`.

## Parameters

`scripts/Test-Dockerfile.ps1`:

| Parameter | Default | Description |
| --- | --- | --- |
| `-Path` | `.` | Dockerfiles or directories. Directories skip `.git`, `.devcontainer`, `node_modules`, `bin`, `obj`, `target` and `deps` |
| `-ImageProfile` | `auto` | `auto` reads `# Profile: <name>`, treats `*.Debug` as `debug`, else `published` |
| `-ContextPath` | Nearest `.git` ancestor | Build context used to find `.dockerignore` |
| `-Skip` | none | Rule identifiers to suppress |
| `-FailOn` | `error` | `error`, `warning` or `never` |

Exit codes: `0` no blocking findings, `2` blocking findings, `1` the audit failed.

## Audit Rules

| Rule | Severity | Finding | Relaxed for |
| --- | --- | --- | --- |
| DF001 | error | Missing or unexpected `# syntax` directive | sample |
| DF002 | error | Untagged or `latest` image | |
| DF003 | error | `--platform` on the final stage | single-arch, sample |
| DF004 | warning | A build stage that runs commands is not pinned to `$BUILDPLATFORM` | single-arch, vendor, sample |
| DF005 | error | No `USER`, or `USER root`, in the final stage | |
| DF006 | error | Shell-form `ENTRYPOINT` or `CMD` | sample |
| DF007 | error | `sh -c` entrypoint without `exec` | sample |
| DF008 | error | apt install without `--no-install-recommends` | sample |
| DF009 | error | apt lists not removed in the same `RUN` and not cache-mounted | sample |
| DF010 | error | Distribution-wide package upgrade | sample |
| DF011 | error | Shell heredoc that does not open with `set -e…` | sample |
| DF012 | error | Platform `case` without `*)`, or `if` chain without `else` | sample |
| DF013 | error | Provenance `ARG` without a default | debug, sample |
| DF014 | error | Provenance `ARG` missing from the final stage | vendor, debug, sample |
| DF015 | error | Required OCI label missing | debug, sample |
| DF016 | error | `HEALTHCHECK` declared | sample |
| DF017 | error | Download piped into a shell | |
| DF018 | warning | Commented-out instruction | sample |
| DF019 | error | No `.dockerignore` for the build context | sample |
| DF020 | error | `.dockerignore` does not start with `*` | sample |
| DF021 | warning | `-dev` or meta-package installed in the runtime stage | sample |
| DF022 | error | Secret-like `ARG` or `ENV` with a value | |
| DF023 | warning or error | Last stage not named `final`, or no `FROM` | sample |
| DF024 | warning | `EXPOSE` in a `job` or `tool` image | sample |
| DF025 | warning | `.dockerignore` re-excludes a build or VCS directory without a trailing `/**` | sample |
| DF026 | error | .NET publish stage diverges from the canonical arguments, offline cache or option order | sample |

Rules about the published image follow `FROM <stage>` inheritance, so `FROM runtime AS final`
inherits the runtime stage's `USER`, entrypoint, provenance and labels. Stages derived from the
runtime, such as `debug`, are not expected to run on `$BUILDPLATFORM`.

Rules that need judgement stay manual. Check each by hand when authoring or migrating:

* Dependency manifests are copied before sources, and runtime configuration such as
  `appsettings.json` only after restore.
* `TARGETARCH` is declared late, and runtime packages are installed before the application copy.
* Restore and publish use the same configuration, and a RID-specific publish runs `--no-restore`.
* A .NET application publish follows the [.NET artifact identity](./dotnet-artifact-identity.md)
  contract: it receives `VERSION` and `GIT_COMMIT` and passes them as MSBuild
  `Version` and `SourceRevisionId`, plus the complete build provenance property set from the
  canonical template; the same version and commit drive the OCI version and revision labels.
* A .NET Dockerfile retains the canonical template's argument order, restore/publish option order,
  line wrapping and stage order except where an adjacent comment explains a workload requirement.
* `WORKLOAD` is the output assembly name, `PROJECT` is the independent project path, publish creates
  the canonical `entrypoint.dll` alias, and every .NET runtime uses the same exec-form entrypoint.
* Published and sibling-project Debug .NET images both retain all six OCI labels; runtime base,
  native packages, ports, writable paths and dependency-copy lists are the expected variable parts.
* Every stage that reads a build argument redeclares it with a default.
* Each `VOLUME` path exists in the image, owned by the runtime user.
* The base image is the smallest suitable one, still inside its publisher's support window.
* Lockfiles are installed in locked mode.

The audit reads Dockerfiles and `.dockerignore` files only. Review Compose files against
`docker.compose.instructions.md`.

## Scripts

Run these commands from this skill's directory, substituting the target repository's absolute
Dockerfile path for the illustrative relative input paths.

```powershell
./scripts/Test-Dockerfile.ps1 -Path ./Dockerfile
./scripts/Test-Dockerfile.ps1 -Path ./Dockerfile.gpu -ImageProfile single-arch
./scripts/Test-Dockerfile.ps1 -Path ~/source/example -FailOn warning | Format-Table Rule, Line, Message
./scripts/Invoke-Tests.ps1
```

Pass several paths as a comma-separated list from PowerShell. From another shell, run
`pwsh -Command "./scripts/Test-Dockerfile.ps1 -Path a,b"`.
