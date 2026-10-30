---
name: patterns-ports-and-adapters
description: 'Design, implement, audit or troubleshoot ports-and-adapters and hexagonal architecture: application-owned contracts, dependency inversion, inbound/outbound adapters, provider substitution, anti-corruption mapping and shared contract tests. Use for external-system boundaries and replaceable integrations, not mandatory project splitting or one interface per class.'
argument-hint: '[design|apply|audit] [capability or adapter boundary]'
user-invocable: true
---

# Ports and Adapters (Hexagonal Architecture)

Put policy on the application side of a deliberate contract and keep technology-specific behavior
in its adapter. Use the boundary where it buys actual substitution, isolation or testability.

## Scope and Resources

- Load [boundary contracts](./references/boundary-contracts.md) for ownership and semantic design,
  and the [provider substitution example](./examples/provider-substitution.md) for a concrete port,
  dependency graph and shared behavioral tests.
- [Modular monolith](../patterns-monolith-modular/SKILL.md) owns module/role composition and layered project
  boundaries. This skill owns the behavior across an integration seam; it does not require a
  monolith, multiple projects, physical tiers or a microservice deployment.
- Use [DI](../dotnet-dependency-injection/SKILL.md) for provider selection,
  [HTTP integrations](../dotnet-http-integrations/SKILL.md) for transport,
  [EF Core](../dotnet-efcore/SKILL.md) and [Redis](../redis-data-access/SKILL.md) for data semantics,
   and [ADR authoring](../docs-adr/SKILL.md) when the requested decision needs a durable record.
- Follow [C# instructions](../../instructions/dotnet.csharp.instructions.md) for interface and error
  conventions. The official
  [architecture guidance](https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures)
  explains inward dependencies and infrastructure independence; its project layout is not mandatory.

## Workflow

1. In `design`/`audit`, report evidence and options without implementation. In `apply`, trace the
   requested use case from input to application policy to external effect before extracting anything.
2. Identify the actual reason for the seam: existing alternate providers, a real fake/test consumer,
   an external library contract or technology coupling that blocks the requested change.
   Do not turn every class into an interface or invent a generic plugin/repository framework.
3. Name the application capability and its owner. Separate inbound adapters (HTTP/CLI/messages
   invoking use cases) from outbound ports (capabilities the use case needs). Inspect actual
   compile-time references and public signatures, not architectural folder names.
4. Define input/output, authority, validation, authorization context, cancellation, failure categories,
   idempotency and consistency before choosing adapter APIs. Ask about material behavioral tradeoffs.
5. Reuse existing contracts/helpers when their semantics fit. Keep application DTOs independent of
   SDK/EF/transport types; map provider models and recognized errors at the adapter boundary.
6. Compare provider capabilities honestly using the reference. Reject unsupported operations
   explicitly or expose deliberate capabilities; do not emulate success or reduce every provider to
   an unusable lowest-common-denominator interface.
7. Wire concrete adapters only at the composition root using existing selection/lifetime mechanisms.
   Keep domain/application code free of service-locator calls, SDK construction and provider switches.
8. Update every affected consumer, mapper, configuration path, test fake and contract document.
   Avoid unrelated restructuring; a narrow seam inside one assembly can be enough.

## Validation and Reporting

With approval, use one shared behavioral suite for the real adapters where isolated execution is
possible and for fakes where appropriate. Cover required success, absence, errors, cancellation,
duplicate requests, unsupported behavior and data isolation. Verify dependency direction separately.

Fake success is not proof of provider compatibility. Clearly distinguish pure mapping/handler tests,
provider-backed tests and live conformance. Do not call real external services or run destructive
provider tests without authorization.

Report the seam's purpose, contract owner, allowed dependency direction, provider differences,
tests executed and limitations. Do not claim strict hexagonal architecture from interface names.

## Maintaining This Skill

Apply the shared [customization feedback loop](../../instructions/workflow.instructions.md#maintaining-conventions)
when using this skill; the triggers below include newly learned topics, not only version drift.

- Incorporate verified boundary, mapping or substitution lessons into the relevant workflow/reference;
  extend the provider example and shared cases when a new capability warrants reusable guidance.
- Revisit contracts when provider capabilities, SDK errors or consistency guarantees change.
- Keep fakes/shared tests aligned with real semantics, including absence, cancellation and conflicts.
- Preserve the scope split: module layout in modular monolith, transport and persistence in their skills.
