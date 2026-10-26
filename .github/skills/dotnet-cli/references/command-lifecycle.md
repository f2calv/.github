# Command Lifecycle and Process Outcomes

## Parse Before Operational Construction

Use the actual parser to distinguish successful help/version, invalid syntax and an executable
command. If it currently builds command descriptors from DI, keep that metadata path free of
operational clients and credential-dependent validation. Do not bypass syntax validation with
`args.Contains("--help")`.

Resolve only command-relevant options. A local conversion command should not fail because a
different cloud command lacks credentials. Do not weaken validation of the selected operation to
make help work.

Separate:

- Parser defaults and explicitly supplied arguments.
- Command selection and application runtime feature selection.
- Dry-run/preview and mutation. A flag named preview is not proof its handler avoids side effects.
- User-facing results, diagnostic logs and process exit status.

## Finite Work

For a finite command needing a host, choose the lifecycle that its dependencies require:

1. Build only the selected composition.
2. Start the host only if required hosted infrastructure must run; mere DI resolution may not need it.
3. Create the command scope and await its operation with the invocation cancellation token.
4. Preserve the operation's known result or exception.
5. Stop any started host with a separate bounded cleanup token, not an already-cancelled
   invocation token. Dispose command scope and host at their ownership boundary.
6. Produce the final process result after accounting for startup, work and cleanup failures.

Do not call `RunAsync` and wait indefinitely when the command itself should determine completion.
Conversely, do not exit before required background work or buffered output is flushed.
Do not use `Environment.Exit` to skip cleanup.

If both work and shutdown fail, preserve the primary failure and expose secondary failure through
the existing safe error policy. Do not throw only from `finally` and mask the original problem.
Scope/host disposal may also fail; a zero exit requires the application's complete success contract.

## Daemons and Cancellation

For a daemon, let the host own lifetime and supervise background faults. `StopApplication` merely
requests shutdown. A background exception can stop the host without setting the desired nonzero
process code; test the entrypoint rather than inferring success/failure from host logging.

Pass cancellation through the actual handler and dependencies. Translate requested cancellation
to the documented CLI result; unrelated timeouts/cancellation remain distinct failures.
Platform signal conventions differ. Do not impose exit code 130 everywhere or hardcode
cross-platform signal assumptions; preserve or explicitly establish the tool's contract.

## Output and Errors

Operational diagnostics use the existing logging path, normally stderr for a machine-readable CLI.
Do not interleave host startup logs, progress text or token values into JSON stdout.
Use the application's established output abstraction for intentional command output, not logging
as a substitute for a stable result schema.

Translate recognized validation/domain failures at the CLI boundary with safe actionable messages.
At the final process boundary, unexpected exceptions can be diagnosed and converted to a nonzero
result by the repository's established handler; they must not be swallowed or mapped to success.
Never echo raw arguments/configuration as an error message.
