---
name: dotnet-dependency-injection
description: 'Design, implement, audit or troubleshoot .NET dependency injection: singleton, scoped and transient lifetimes, captive dependencies, provider/strategy factories, keyed services, shared-instance aliases, disposal, hosted-service scopes and test substitutions. Use for DI registration and resolution failures or composition refactoring, not distributed singleton election.'
argument-hint: '[design|apply|audit|diagnose] [service or composition root]'
user-invocable: true
---

# .NET Dependency Injection

Make service construction, lifetime and resource ownership explicit without building a second
container or adding an interface/factory for every class.

## Authorities and Resources

- Follow the [C# instructions](../../instructions/dotnet.csharp.instructions.md) for constructor,
  interface and composition-root conventions, and the
  [configuration instructions](../../instructions/dotnet.configuration.instructions.md) for options.
- Load [lifetimes and factories](./references/lifetimes-and-factories.md) for selection, scopes,
  aliases and disposal. The [worked example](./examples/provider-selection-and-scopes.md) combines
  configuration-selected providers with one process-local broker and per-job scopes.
- Use [modular monolith](../patterns-monolith-modular/SKILL.md) for module/role composition,
  [EF Core](../dotnet-efcore/SKILL.md) for context lifetimes,
  [background pipelines](../dotnet-background-pipelines/SKILL.md) for worker supervision and
  [leadership election](../leadership-election/SKILL.md) for distributed ownership.
- Verify framework behavior in the official
  [DI guidelines](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/guidelines).

## Workflow

1. Establish the requested mode. `audit` and `diagnose` report evidence without edits; `design`
   proposes boundaries; `apply` changes the requested registrations and consumers.
2. Trace registration through actual resolution: composition extensions, assembly scans, conditional
   roles, keyed/named selection, hosted services and tests. Record the effective registration order,
   not just the first `AddSingleton` found.
3. For each affected service, record implementation, lifetime, dependencies, mutable state,
   construction/disposal owner and consumers. A singleton is one instance per provider, not one
   per machine, deployment or cluster; inspect accidental extra providers.
4. Choose the shortest valid lifetime. Request/unit-of-work state is scoped; stateless behavior
   can be transient; genuinely shared, thread-safe state may be singleton. A singleton must not
   capture request services, a context, a scoped options snapshot or a transient typed HTTP client.
5. Search shared registration helpers before adding new ones. Keep resolution/factories in the
   composition boundary, not hidden behind application service locators. Use a narrow factory only
   where runtime selection or independent operation lifetime actually requires it.
6. Define provider selection: startup-only or per operation, allowed values, invalid/absent input,
   default policy and reload support. Never silently choose a provider when configuration is invalid.
   Register/validate only required dependencies where inactive integrations need no credentials.
7. Apply ownership and alias rules from the reference. Keep independently scoped work inside an
   awaited async scope; do not let tasks or scoped objects escape it.
8. Update every affected interface consumer, registration, test substitution and configuration
   example. Preserve public contract compatibility unless the requested change includes migration.

## Validation and Reporting

Ask before tests/builds. With authorization, use existing DI tests and scope/build validation,
then resolve the affected supported compositions. Validation cannot prove thread safety, runtime
factory branches or correct disposal by itself.

Cover unknown selection, every supported provider, missing dependency, shared-instance identity,
per-scope isolation, concurrent singleton use and disposal on success/failure. Verify async-only
disposables via async scopes. Do not construct real integrations or contact external services
merely to validate the graph.

Report the effective graph, lifetime/ownership changes, preserved selection behavior, checks run and
remaining runtime risks. Do not commit or deploy as a side effect of wiring.

## Maintaining This Skill

Apply the shared [customization feedback loop](../../instructions/workflow.instructions.md#maintaining-conventions)
when using this skill; the triggers below include newly learned topics, not only version drift.

- Incorporate verified lifetime, factory or ownership lessons into the relevant workflow/reference;
  extend the worked example and acceptance cases when they demonstrate a reusable scenario.
- Recheck container validation, keyed-service behavior and disposal semantics when .NET changes.
- Update examples when shared registration helpers or provider-selection contracts change.
- Keep distributed ownership, worker supervision and EF context policy in their linked authorities.
