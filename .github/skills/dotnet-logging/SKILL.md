---
name: dotnet-logging
description: 'Design, audit, tune or troubleshoot .NET operational logging: balancing noisy and quiet output, level policy per workload, request summaries, Serilog level layers (minimum, category overrides, sink thresholds), runtime level switches, privacy-safe properties, duplicate events and OpenTelemetry forwarding. Use when logs are too noisy, too quiet, duplicated or leak data. Message-template style belongs to the C# instructions and hot-path logging mechanics to dotnet-performance.'
argument-hint: '[design|apply|audit|diagnose] [application or symptom]'
---

# .NET Logging

Operational logs must be useful at the default level without anyone raising it. Too noisy and the
signal drowns and sinks cost money; too quiet and an incident has no trail. Strike the balance with
an explicit event budget per level, not by turning verbosity up or down.

## Authorities

- [C# instructions](../../instructions/dotnet.csharp.instructions.md) own message templates,
  correlation scopes, `[LoggerMessage]`, `IsEnabled` guards and the never-log list.
- [Configuration instructions](../../instructions/dotnet.configuration.instructions.md) own provider
  layering, immutable startup snapshots and secret safety.
- [AppHost](../dotnet-apphost/SKILL.md) owns where logging, telemetry and middleware are registered;
  [Web API](../dotnet-webapi/SKILL.md) owns the controller and error-handling boundary;
  [performance](../dotnet-performance/SKILL.md) owns allocation-free hot-path logging.
- The [level policy reference](references/level-policy.md) holds the per-workload event budget,
  the failure-transition pattern and worked examples.

## Modes

| Mode | Outcome |
| --- | --- |
| `design` | Propose the event set, levels and configuration for a host without editing |
| `apply` | Change logging calls, request summaries or configuration to the agreed contract |
| `audit` | Report noise, gaps, duplicates, leaks and configuration drift with evidence |
| `diagnose` | Explain why an expected event is missing, duplicated or unexpectedly present |

## Workflow

### 1. Inventory the Pipeline

Trace the executed configuration, not the file names:

1. bootstrap logger, host logger and who owns the pipeline (Serilog with `writeToProviders`, or
   Microsoft logging with Serilog as a provider);
2. sinks and forwarded providers (console, OpenTelemetry, files) and their output format;
3. the pipeline minimum, every category override and every sink threshold or level switch, with
   where each value comes from: code default, `appsettings*.json`, environment or runtime store;
4. enrichers, scopes and which properties they attach;
5. request-summary middleware and its position; framework request logging such as `AddHttpLogging`;
6. which settings change at runtime and which need a restart.

### 2. Apply the Event Budget

The [level policy](references/level-policy.md) is the contract. Its core rules:

- **Information scales with work and state changes, never with time.** Startup and shutdown,
  configuration activation, leadership and connection transitions, one summary per request or
  unit of work, and recovery. An idle service at Information is nearly silent.
- **Debug** holds per-item progress, successful polls, cache hits and misses, skipped or disabled
  features, standby loops and repeats of an already reported failure.
- **Warning** is degraded but continuing, and needs attention if it persists; **Error** is a failed
  unit of work someone must act on; **Critical** means the process cannot continue.
- **Log transitions, not steady state**: a recurring failure logs one Warning, repeats at Debug,
  and logs one Information on recovery with the failure count and duration.
- **Log each fact once**, at the boundary that handles it: one exception event, one request summary.
  Never log and rethrow, and do not repeat in a controller what the service or middleware logs.
- **Prefer aggregation to sampling**: a periodic count or batch summary keeps the signal that random
  sampling loses. Sample only measured high-volume Debug events.

### 3. Summarize Requests Safely

Emit one completion event per HTTP request from host middleware, not from controllers:

- method, matched **route template** (never the raw path or query string), status code and elapsed
  time; correlation comes from `RequestId` and trace identifiers;
- **levels**: unhandled exception or 5xx `Error`; failed health probe or slow non-streaming request
  `Warning`; other responses `Information`; client cancellation and unmatched 404 `Debug`;
  successful health probes and static files `Verbose`;
- register it **first**, before the exception handler, so it times the whole pipeline, records
  authentication and authorization rejections and leaves the exception event to the handler;
- keep the framework's own per-request `Information` lines (`Microsoft.AspNetCore` hosting and
  routing) behind a `Warning` override so each request produces one line, not three;
- never enable request or response body, header or cookie logging (`AddHttpLogging`,
  `UseW3CLogging`, custom middleware) by default; scope any diagnostic use to an operator-controlled
  destination and expiry, following the shared operator-diagnostics rule;
- ASP.NET Core's hosting scope attaches the raw `RequestPath` to **every** event during a request;
  remove it in the pipeline where paths can carry identifiers.

For example, the public
[CasCap.Common.Hosting.AspNetCore](https://github.com/f2calv/CasCap.Common/tree/main/src/CasCap.Common.Hosting.AspNetCore)
library implements these rules in `UseCasCapRequestLogging` and `AddCasCapDefaults`. Where the
application already uses such a shared library, adopt it rather than copying the middleware.

### 4. Configure the Level Layers

Three independent layers decide whether an event is written. Change the layer that matches intent:

| Layer | Controls | Typical setting |
| --- | --- | --- |
| Pipeline minimum | Every category without an override | `Information` in every deployed environment |
| Category overrides | Named namespaces, independent of the minimum | Framework namespaces at `Warning`; a noisy dependency raised; one application namespace lowered while diagnosing |
| Sink thresholds | One destination only; can only drop further | Console raised for an interactive UI; never used to hide production noise |

- Lowering the minimum does not reveal categories with an override, and it never creates events
  that code does not emit. Diagnose a quiet log in this order: is the event produced, is it
  filtered by the minimum, an override or a sink threshold, and is it delivered by the transport.
- Keep shared defaults in code and restate in `appsettings*.json` only deliberate deviations. A
  Development override may lower the application's own namespaces to `Debug`.
- Deployed levels are part of the immutable startup snapshot. The only runtime exception is a typed,
  authorized, time-bounded level switch on the actual pipeline that expires back to the startup
  baseline. Category overrides, sinks and formats stay restart-only unless separately designed.
- Choose one pipeline owner and one console writer, so that every event reaches each sink exactly
  once and OpenTelemetry forwarding stays registered after provider clearing.
- Use structured output for machine-collected sinks and readable text for interactive consoles;
  keep property names identical across both.

### 5. Validate

Ask before running tests or starting hosts. Prefer an in-process host with an in-memory sink and
captured forwarded-provider records over live environments. Prove:

- an ordinary request emits exactly one summary with the route template and no raw identifier,
  query value or synthetic secret, including in properties added by scopes and enrichers;
- successful health probes and static files are suppressed; failures stay visible;
- an exception produces one exception event, and the summary does not repeat its stack trace;
- a generated `Debug` event is dropped at `Information` and written at `Debug` through the real
  pipeline, and overrides and sink thresholds behave as documented;
- a runtime level change applies to the actual pipeline and expires back to the startup baseline;
- startup, normal work, cancellation, shutdown and failure output is coherent for each host shape;
- each event reaches each sink once, and the forwarded provider receives it.

For broad level-guard or privacy sweeps, also require the existing duplication and cognitive
complexity checks. Consolidate repeated operation logging rather than copying guarded catch
blocks; behavior tests alone do not establish maintainability.

## Reporting

Report the pipeline inventory, the event budget applied per workload, configuration layers before
and after, events added, demoted or removed with their reasons, privacy findings, validation run
and not run, and remaining noise or gaps.

Do not commit, push, publish or deploy, or raise production levels, without separate authorization.
Never increase verbosity only to flush a buffering proxy or to make a log viewer look busy.

## Maintaining This Skill

- Recheck Serilog.AspNetCore request-logging options, hosting scope properties and
  `writeToProviders` forwarding on each major ASP.NET Core and Serilog upgrade.
- Recheck .NET exception-handler diagnostics suppression, which can remove or duplicate the
  exception event.
- Fold verified noise and leak findings from audits into the level policy reference, not here.
- Keep the request-summary rules aligned with the CasCap.Common helper and its tests.
