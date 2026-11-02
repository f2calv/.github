---
name: scripting-tests
description: 'Write, run and troubleshoot unit tests for PowerShell, Python and Bash scripts with Pester 5, pytest and bats-core: test layout, fake commands on PATH, temporary workspaces, shared fixtures that keep implementations in different languages in parity, local container runs and CI steps. Use when adding or changing a .ps1, .py or .sh script or its tests; .NET test projects belong to dotnet-test-platform.'
argument-hint: '[language={powershell|python|bash}] [mode={write|run|parity|ci}] [script=path]'
---

# Scripting Tests

Unit tests for scripts: Pester 5 for PowerShell, pytest for Python and bats-core for Bash. The
language instructions hold the always-on rules
([PowerShell](../../instructions/shell.powershell.instructions.md),
[Python](../../instructions/python.instructions.md),
[Bash](../../instructions/shell.bash.instructions.md)); this skill holds the procedures.

Never run tests without the user's approval: they may reach credentials or external services.

## Modes

| Mode | Use for |
| --- | --- |
| `write` | Adding tests for a new or changed script |
| `run` | Running a suite locally, natively or in a disposable container |
| `parity` | Keeping implementations of one tool in several languages behaviourally identical |
| `ci` | Adding or changing the workflow steps that run the suites |

## Principles

- **Test behaviour through the script's real interface.** Run the script as a process with its
  real arguments and assert on exit code, output and files, rather than importing private helpers.
  Unit-test a pure helper directly only when it carries genuinely tricky logic.
- **Fake external commands on `PATH`.** Place a small executable named like the real tool (`specify`,
  `gh`, `curl`) first on `PATH`. It records its arguments to a log and simulates side effects, so
  tests never reach real services, credentials or the network.
- **Isolate every test in a temporary workspace**: Pester `$TestDrive`, pytest `tmp_path`, bats
  `$BATS_TEST_TMPDIR`. Never touch the repository working tree or the user's profile.
- **Use synthetic data only**: placeholder IDs, `example.com` URLs and fixed hashes.
- **Cover each path**: success, every distinct error, the no-op path, `-WhatIf` where it exists,
  and idempotent reruns. Assert the exact changed surface for scripts that write files.
- **Name tests for the behaviour** they prove: `refuses to remove a skill another skill requires`.
- **Assert exit codes as well as output.** A failing command must fail with exit code 1 and its
  message on stderr.

## Workflow

1. Identify the language and read its reference: [Pester](references/pester.md),
   [pytest](references/pytest.md) or [bats-core](references/bats.md).
2. Place tests beside the script's other tests in the layout the reference describes. Add or
   extend fakes and fixtures before writing assertions.
3. Write one test per behaviour. For a tool implemented in several languages, follow the
   [parity reference](references/parity.md): shared fixtures, shared fakes and identical scenario
   lists in every suite.
4. With approval, run the suite natively or in the container the reference names, and read the
   executed test count; zero executed tests is a failure.
5. Wire new suites into CI as the reference shows, and keep linters (ruff and mypy, shellcheck) in
   the same job as the tests they guard. When a repository tests scripts in several languages,
   define one-shot `compose.yaml` services behind a `test` profile with a read-only source mount, and
   run them in CI with `docker compose run --rm <service>` so local and CI toolchains match.

## Maintaining This Skill

- Pinned versions: Pester 5.7.1, pytest, bats-core, bats-support, bats-assert, the
  `bats-core/bats-action` and `astral-sh/setup-uv` releases, and the container images in the
  references.
- Spec Kit's script variants (`ps`, `sh`, `py`) when the skill library helper's parity suites change.
- New pitfalls found while writing tests, in the reference for that language.
