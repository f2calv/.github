---
name: patterns-architecture-review
description: 'Assess an application''s architecture for evidence-backed smells and plan a proportionate realignment of code to its architecture views. Use after drawing context, container and component diagrams, when a codebase is convoluted or hard to change, to find dependency cycles, inverted dependencies, hub components, scattered responsibilities, leaky boundaries, shared data ownership or speculative abstraction, and to rearrange folders, projects and visibility so the code matches its component view.'
argument-hint: 'mode={assess|realign} [scope=repository|container] [target=path to target view]'
---

# Architecture Review

Find where an application's structure costs its maintainers time, and propose the smallest change
that removes that cost. The review starts from the architecture views, not from a pattern catalogue:
a smell is reported because it has a concrete effect on this codebase, never because the code
departs from an idealized style.

## Scope and Authorities

| Concern | Authority |
| --- | --- |
| Smell catalogue, evidence, severity and proportionality | This skill and the [smell catalogue](./references/smells.md) |
| Context, container and component views and the code map the review starts from | [Architecture diagrams](../docs-architecture-diagrams/SKILL.md) |
| Module boundaries, dependency direction and one-image roles | [Modular monolith](../patterns-modular-monolith/SKILL.md) |
| Application-owned ports, adapters and provider substitution | [Ports and adapters](../patterns-ports-and-adapters/SKILL.md) |
| Service lifetimes and composition-root changes | [.NET dependency injection](../dotnet-dependency-injection/SKILL.md) |
| Recording a target architecture and its tradeoffs | [ADR authoring](../docs-adr/SKILL.md) |
| Renames, moves, commits and history preservation | [Workflow instructions](../../instructions/workflow.instructions.md) |

## Modes

| Mode | Outcome |
| --- | --- |
| `assess` | A findings report with evidence, severity, confidence and a proportionate recommendation for each smell. Read-only. |
| `realign` | A phased plan, and on approval its execution, that moves code until the code map matches a target components view. |

Neither mode rewrites behavior. Realignment moves, renames and narrows visibility; logic changes that
a finding suggests are separate work.

## Assess

1. **Obtain the views.** Use the repository's current System Context, Containers, Components and
   Code Map. When they are missing or stale, produce them first with the
   [architecture diagrams skill](../docs-architecture-diagrams/SKILL.md) in `explain` mode; the
   review is only as good as the views.
2. **Collect measurements.** Derive them from source and manifests rather than estimating:
   project and package references, namespace or folder imports between components, constructor
   dependencies of each component's main types, file counts and sizes per component, partial-class
   spread, interface-to-implementation counts, shared tables or keys, and change coupling from
   `git log` when history is available.
3. **Match smells.** Walk the [smell catalogue](./references/smells.md). For each candidate, record
   the evidence, where it shows in the views, and the concrete cost it causes or risks. Check the
   catalogue's "not a smell when" conditions before reporting.
4. **Rate each finding.** Severity reflects cost; confidence reflects evidence quality:

   | Severity | Meaning |
   | --- | --- |
   | High | Blocks independent change or deployment, or creates a correctness or security risk |
   | Medium | Makes common changes slower, riskier or harder to review |
   | Low | Hinders understanding; worth fixing when the area is next touched |

   Confidence is 1 to 10. Report below 5 only as an open question.
5. **Recommend proportionately.** For every finding offer the smallest effective change, the
   expected benefit and its cost. "Leave as is and document the decision" is a valid
   recommendation and is often the right one for stable code nobody needs to change.
6. **Report.** Lead with a summary table, then one section per finding:

   | # | Severity | Smell | Where | Evidence | Confidence |
   | --- | --- | --- | --- | --- | --- |

   Close with what was checked and found healthy, so the report does not read as a list of
   complaints, and with the measurements that would change a rating.

Keep findings in the session workspace or the conversation by default. Publish them to a repository
issue or document only on request, after the [repository privacy](../repository-privacy/SKILL.md)
check when the destination is public.

## Realign

Use realignment when the user asks to make the code resemble a view, for example "see the
components view; now rearrange the classes to match it".

1. **Fix the target.** Agree a target components view and code map. When it differs from the
   current one, record it as a proposed ADR with the [ADR skill](../docs-adr/SKILL.md);
   documentation keeps describing current code until the move lands.
2. **Diff the maps.** For each component, list the files whose location differs from the target,
   the types that cross component boundaries, and the references that point the wrong way.
3. **Plan phases that each keep the build green**, smallest risk first:
   1. Move files into component folders with `git mv`, without changing namespaces or code.
   2. Align namespaces with the new folders.
   3. Narrow visibility: make types `internal` that no other component uses, and route remaining
      cross-component use through the component's ports.
   4. Break wrong-direction references by moving the shared contract to the component that owns it,
      or introducing a port owned by the consumer.
   5. Split into projects or modules only when a measured need exists: independent release,
      enforced isolation or build time.
   6. Add architecture tests that pin the new boundaries, such as allowed references between
      component namespaces, using the ecosystem's architecture-testing library.
4. **Confirm before executing.** Present the phases with their file counts and risks and wait for
   approval. Commit each completed phase separately, following the workflow instructions.
5. **Update the views.** After the final phase, update the components view and code map in the
   same change, and mark the ADR accepted.

## Maintaining This Skill

- Architecture-testing libraries for each ecosystem and their supported rule types.
- Static-analysis tooling that can supply reference, coupling or cycle measurements.
- The smell catalogue when a finding proves unhelpful in practice or a recurring problem is missing.
