---
name: dotnet-cli
description: 'Create, extend, audit or troubleshoot .NET command-line applications: argument parsing, commands, help/version, configuration precedence, lazy credentials, Generic Host startup/shutdown, finite jobs versus daemons, cancellation, stdout/stderr contracts and process exit codes. Use for console entrypoints and administrative modes, not general dotnet SDK commands.'
argument-hint: '[apply|audit|diagnose] [command or entrypoint]'
user-invocable: true
---

# .NET CLI Applications

Make a command's syntax, side effects, lifetime, output and exit status agree. A finite command is
not a background worker that happens to stop eventually.

## Authorities and Resources

- Follow [C#](../../instructions/dotnet.csharp.instructions.md) and
  [configuration](../../instructions/dotnet.configuration.instructions.md) conventions.
- Load [command lifecycle](./references/command-lifecycle.md) and the
  [finite-command example](./examples/finite-command-and-help.md) for dispatch and exit contracts.
- Use [DI](../dotnet-dependency-injection/SKILL.md) for construction/ownership,
  [modular monolith](../modular-monolith/SKILL.md) for one-image roles,
  [background pipelines](../dotnet-background-pipelines/SKILL.md) for supervised workers and
  [EF Core](../dotnet-efcore/SKILL.md) for migration/seeding modes.
- The official [Generic Host documentation](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host)
  owns hosting APIs. If using a parser package, verify its installed version before copying APIs;
  do not add or migrate command frameworks for an unrelated command change.

## Workflow

1. In audit/diagnose mode, report without edits. Otherwise trace the real process entrypoint,
   parser, configuration sources, command handlers, host registration and deployment invocation.
   Inventory supported commands/options, aliases, defaults and current exit/output behavior.
2. Classify each path: help/version, syntax failure, finite read, finite mutation, or daemon.
   Define cancellation, required dependencies, output, exit status and mutation authorization.
   Preserve intended behavior; ask before changing defaults, failure codes or destructive semantics.
3. Reuse the existing parser. Parse complete syntax without starting the operational host or
   constructing credentials/external clients for help/version. Do not use ad-hoc substring detection
   that interprets a value named `--help` as a global help request.
4. Bind effective configuration with explicit CLI values overriding configuration. Distinguish
   omitted options from parser defaults so defaults do not overwrite a configured value.
   Keep credentials available through configuration rather than requiring process-visible arguments.
5. Register and validate the selected command's dependencies only. Keep `Program` wiring-only and
   business work in its existing application service; do not start unrelated workers for a finite job.
6. Apply the lifecycle reference. Await command completion, bounded host shutdown and disposal.
   Map known outcomes to explicit process results; unexpected faults remain failures.
7. Update help, configuration examples, scripts, task definitions and container invocation surfaces
   affected by the command. Keep machine-readable stdout separate from diagnostic logging.

## Validation and Reporting

With approval, run existing parser/handler tests and isolated process tests. Assert help/version
with missing credentials, invalid syntax, explicit-versus-omitted option precedence, finite
completion, cancellation, startup/work/shutdown failures, exact exit codes and output shape.
Do not settle for an in-process handler returning a value; verify the actual process returns it.

Never exercise a real migration, external mutation or daemon as a help smoke test. Use fake
dependencies and temporary resources with bounded process timeouts.
Report command contracts, compatibility changes, executed validation and live behavior not tested.

## Maintaining This Skill

Apply the shared [customization feedback loop](../../instructions/workflow.instructions.md#maintaining-conventions)
when using this skill; the triggers below include newly learned topics, not only version drift.

- Incorporate verified parsing, output or lifecycle lessons into the relevant workflow/reference;
  extend the command example and process cases without imposing one tool's exit codes on others.
- Recheck parser invocation APIs, defaults and help behavior when package versions change.
- Revisit host exception/exit behavior and signal handling on SDK or deployment-platform changes.
- Keep examples aligned with the supported output schema, command outcomes and shutdown deadlines.
