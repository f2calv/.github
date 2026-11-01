# Lifecycle Scripts

Design Dev Container lifecycle hooks and scripts that are fast, idempotent and free of side effects.

Keep lifecycle behavior in scripts rather than long JSON command strings.

The reusable [tool verifier](../scripts/Initialize-DevContainer.ps1) checks an exact installed
Pester version and caller-selected executables without installing packages. Keep repository tool
selection in a thin local lifecycle entry point; specialized installers belong to their owning
skills. The [composition tests](../scripts/tests/Initialize-DevContainer.Tests.ps1) exercise this
repository's entry point with mocked tools, not a live container build.

Lifecycle order is `initializeCommand`, `onCreateCommand`, `updateContentCommand`,
`postCreateCommand`, `postStartCommand`, then `postAttachCommand`.

* `initializeCommand` runs on the host before creation. Keep it portable and free of secrets.
* `onCreateCommand` runs in the container during its first creation.
* `updateContentCommand` runs when workspace content is created or updated. Put dependency
  restoration here when it must follow content changes.
* `postCreateCommand` runs after creation and content setup. Use it for final one-time setup and
  concise tool summaries.
* `postStartCommand` runs on every start. Keep it fast, idempotent, and free of repository churn.
* `postAttachCommand` runs on every editor attach and should contain only attach-specific work.
* Never authenticate, mutate remote systems, apply infrastructure, or change clusters from hooks.
* Avoid unconditional operating-system upgrades on every start; they are slow and nondeterministic.
* Do not create a Python virtual environment in lifecycle scripts. Install requirements into the
  image's interpreter or with `pip install --user`, and add `~/.local/bin` to `PATH` through
  `remoteEnv`. Follow the Python instructions for the exceptions.
* Do not auto-install per-commit hooks. Document manual linting and optionally offer
  `pre-commit install --hook-type pre-push --install-hooks`.
* Follow the repository's shell instructions: strict error handling, quoted expansions, validated
  inputs, and clear diagnostics.
* A script invoked through `bash` or `sh` does not require an executable bit.
