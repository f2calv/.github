---
name: patterns-architecture
description: 'Select and declare evidence-backed architecture and namespace profiles for applications and capability library suites. Use for architecture deep dives, flattened versus hierarchical namespace ownership and alignment decisions, including .NET public API and RootNamespace concerns. Routes modular-monolith implementation, diagrams and smell reviews to their focused skills; does not duplicate their procedures.'
argument-hint: '[design|apply|audit|diagnose] [application, library suite or namespace boundary]'
---

# Architecture Patterns and Namespace Profiles

Choose architecture from actual runtime and consumer boundaries, not project names. This
language-neutral entry point owns profile selection and declaration, not each pattern's
implementation. Language-specific namespace mechanics live in clearly scoped references.

## Scope and Authorities

| Concern | Authority |
| --- | --- |
| Architecture profiles and review routing | This skill |
| Module boundaries, runtime-role composition, lifecycle and implementation | [Modular monolith](../patterns-modular-monolith/SKILL.md) |
| Flattened versus hierarchical namespace ownership | [Namespace profiles](./references/namespaces.md) |
| .NET roles, RootNamespace, CLR identity, collisions and migration | [.NET namespaces](./references/dotnet-namespaces.md) |
| Published-library inventory and API boundary review | [Library suites](./references/library-suites.md) |
| Source-backed architecture views and code map | [Architecture diagrams](../docs-architecture-diagrams/SKILL.md) |
| Smells, evidence, ratings and proportionate realignment | [Architecture review](../patterns-architecture-review/SKILL.md) |
| Integration contract semantics and provider substitution | [Ports and adapters](../patterns-ports-and-adapters/SKILL.md) |
| Consequential target decisions and alternatives | [ADRs](../docs-adr/SKILL.md) |

## Select the Architecture Profile

| Profile | Evidence required | Not implied |
| --- | --- | --- |
| `modular-monolith` | Cohesive application modules, deliberate contracts and dependencies within an application deployment boundary | One project per module, independent service deployment or strict isolation from runtime flags |
| `capability-library-suite` | Separately consumable libraries with capability-owned APIs, explicit package dependencies and consumer-owned composition | A deployed application, one host or a shared database owned by the suite |

Profiles describe different axes from ports/adapters and logical layering. A modular monolith can
use both; a library suite can supply its adapters. Record the chosen profile and its proven
boundaries. Do not claim that neighboring applications conform without reviewing them.

Other architectures are valid when supported by the actual system; these profiles are not a
mandatory rewrite or an exhaustive catalogue. The focused modular-monolith skill includes its
one-image runtime-role guidance and labelled .NET examples. Invoke it for that work rather than
copying its workflow here.

## Namespacing

Choose namespace ownership separately from deployment topology. Flattened roles serve a shared
consumer API; a module hierarchy makes application ownership visible. Neither arrangement enforces
an architectural boundary on its own.

The [namespace profiles](./references/namespaces.md) define the choice and its constraints.
The [.NET reference](./references/dotnet-namespaces.md) supplies concrete library/application
defaults and generated-code/public-identity checks. Do not impose .NET syntax or its flattening
defaults on other ecosystems.

## Workflow

1. Resolve the requested repository, mode and publication scope. Read its instructions, existing
   views and dirty-worktree state. Preserve unrelated work and separate observed facts from targets.
2. Classify the architecture using manifests, runtime entry points and actual consumers. For a
   library suite, follow the [library review](./references/library-suites.md); for a modular
   monolith, use the [focused skill](../patterns-modular-monolith/SKILL.md).
3. Derive the views and code map with the diagrams owner. Do not invent containers for library
   packages. Use the review owner for source-backed findings, including healthy boundaries.
4. Select the namespace profile and applicable language reference. Inspect actual public identities
   and toolchain constraints, not merely folder paths; measure collisions and consumer costs.
5. Present consequential decisions before implementation: boundary changes, public namespaces,
   type names, metadata and release implications. `design` and `audit` are read-only; `apply`
   executes only the agreed scope. `diagnose` follows the concrete failure through its owner.
6. Declare the chosen architecture and namespace profiles in repository instructions with a link
   here. Keep only repository-specific constraints and approved deviations locally; distinguish
   an agreed target from completed conformance.
7. Validate changed contracts with the existing build, API, package and runtime checks, obtaining
   execution approval. Report exact evidence, unresolved decisions and unverified behavior.

## Maintaining This Skill

- Keep this entry point small: link to focused pattern skills rather than absorbing or duplicating
  them. Local documents retain their own topology, decisions and actual role matrices.
- Reconcile namespace rules with this owner rather than introducing folder-mirroring rules elsewhere.
- Preserve specialized owners for hosting, DI, transport, persistence, containers and review mechanics.
- Incorporate source-backed collision, resource and generated-code lessons into the relevant reference.
- Separate language-neutral ownership decisions from language-specific syntax, defaults and tooling.
