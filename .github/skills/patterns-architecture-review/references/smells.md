# Smell Catalogue

Architecture smells that the [architecture review](../SKILL.md) reports, and that the
[architecture diagrams skill](../../docs-architecture-diagrams/SKILL.md) names in its signals.
Each entry states how it shows in the views, the evidence that confirms it, why it costs something,
when it is not a smell, and the smallest effective response.

A pattern is not a goal. Do not report a smell whose cost cannot be stated for this codebase.

## Summary

| Smell | Typical view | Usual severity |
| --- | --- | --- |
| [Hidden components](#hidden-components) | Code map | Low to Medium |
| [Scattered component](#scattered-component) | Code map | Medium |
| [Hub component](#hub-component) | Components | Medium to High |
| [Dependency cycle](#dependency-cycle) | Dependency graph, Components | High |
| [Inverted dependency](#inverted-dependency) | Dependency graph | Medium to High |
| [Leaky boundary](#leaky-boundary) | Components, Code map | Medium |
| [Shared data ownership](#shared-data-ownership) | Containers, Components | Medium to High |
| [Distributed monolith](#distributed-monolith) | Containers | High |
| [Chatty interaction](#chatty-interaction) | Runtime scenario | Medium |
| [Hidden coupling](#hidden-coupling) | None; that is the problem | Medium |
| [Speculative abstraction](#speculative-abstraction) | Components, Code map | Low |
| [Orphan component](#orphan-component) | Components | Low |
| [Unmappable structure](#unmappable-structure) | Components | Medium |

## Hidden Components

- **Shows as**: a components view whose boxes do not correspond to folders, projects or namespaces.
  The code is organized by technical layer (`Controllers/`, `Services/`, `Models/`, `Abstractions/`)
  and components appear only as recurring file-name prefixes.
- **Evidence**: count files per prefix in layer folders; check whether a typical change touches the
  same prefix in several layer folders.
- **Cost**: readers cannot find a responsibility's boundary; every type is reachable by every other,
  so boundaries erode silently.
- **Not a smell when**: the container is small, roughly under thirty types, or the layer folders
  each contain one component's worth of code.
- **Response**: move files into component folders, then narrow visibility. See Realign in the
  review skill.

## Scattered Component

- **Shows as**: a code map row listing many unrelated locations, or one responsibility split across
  several projects.
- **Evidence**: file locations per component; change coupling showing those locations always change
  together.
- **Cost**: a change to one responsibility touches many places; ownership is unclear.
- **Not a smell when**: the split follows a deliberate deployment or publication boundary, such as a
  published contracts package.
- **Response**: consolidate into one location, keeping only deliberately published contracts apart.

## Hub Component

- **Shows as**: one component with far more incoming or outgoing edges than its peers, or a type with
  a long constructor parameter list, many partial files or a very large file.
- **Evidence**: edge counts per component; constructor parameter counts; lines per type; partial
  files per type; how often the component appears in commits for unrelated features.
- **Cost**: unrelated changes collide in one place; tests need extensive setup; reviews are hard.
- **Not a smell when**: the component is a thin orchestrator or composition root whose dependencies
  are each used once and that holds no logic of its own.
- **Response**: identify the separate responsibilities by grouping its members by the dependencies
  they use, then extract the largest group behind a port.

## Dependency Cycle

- **Shows as**: a cycle in the dependency graph, or a pair of components with edges both ways.
- **Evidence**: project references; namespace imports between component folders.
- **Cost**: neither side can change, be tested or be released independently; build order becomes
  fragile.
- **Not a smell when**: never between projects. Within a component it is ordinary.
- **Response**: move the shared type to the side that owns its meaning, or introduce a port owned by
  one side and implemented by the other.

## Inverted Dependency

- **Shows as**: an edge from a core or backend unit to a user interface, adapter, test or host unit;
  or application code referencing a provider SDK type directly.
- **Evidence**: project references and imports pointing outward; contracts defined in a consumer's
  project.
- **Cost**: the core cannot be reused or tested without the outer unit; changes to the outer unit
  ripple inward.
- **Not a smell when**: the referenced unit holds only contracts that both sides genuinely share and
  nothing else, and moving them would add a project for no other benefit. Record that decision.
- **Response**: move the contracts to a project the core owns, or to a shared contracts project, and
  reverse the reference.

## Leaky Boundary

- **Shows as**: components that depend on another component's internal types rather than its ports;
  external SDK or persistence types crossing a port.
- **Evidence**: types used across component folders that are not listed under Provides in the code
  map; public visibility on types used by one component only.
- **Cost**: internal changes break other components; a provider cannot be replaced.
- **Not a smell when**: the types are immutable value objects that are part of the published model.
- **Response**: narrow visibility, then add the missing port or mapping.

## Shared Data Ownership

- **Shows as**: several containers or components writing the same tables, keys or files.
- **Evidence**: entity or table usage per component; cache-key prefixes written by several
  components; migrations touched by several features.
- **Cost**: invariants are enforced in several places or none; schema changes need coordinated
  releases.
- **Not a smell when**: one component writes and the others only read through a projection it owns,
  or the containers are roles of one application deployed together from one image.
- **Response**: name a single writing owner per table or key family and route other writes through
  its port.

## Distributed Monolith

- **Shows as**: separately deployed containers that share a database schema, a code library with
  domain logic, or a release cadence.
- **Evidence**: shared projects or packages containing logic; coordinated deployments; synchronous
  call chains across containers for one request.
- **Cost**: the operational cost of distribution without independent change.
- **Not a smell when**: the containers are deliberate roles of one modular monolith image and are
  documented as such.
- **Response**: merge into one deployable with configured roles, or separate data and contracts
  properly. Prefer merging unless independent scaling or release is a measured need.

## Chatty Interaction

- **Shows as**: a runtime scenario with repeated calls across a container boundary inside a loop, or
  a long synchronous chain of containers for one request.
- **Evidence**: call sites inside loops that cross a network boundary; request traces.
- **Cost**: latency and failure probability grow with each hop.
- **Not a smell when**: volumes are small and bounded and measurements show acceptable latency.
- **Response**: batch the calls, move the data closer, or make the hand-off asynchronous.

## Hidden Coupling

- **Shows as**: nothing in the static views, which is the problem. Components coordinate through
  shared configuration keys, magic strings, cache-key conventions, reflection or ordering
  assumptions in the composition root.
- **Evidence**: identical string literals in several components; registration order dependencies;
  service-locator calls.
- **Cost**: refactoring breaks behavior without a compiler error.
- **Not a smell when**: the shared key is defined once as a constant owned by one component.
- **Response**: make the dependency explicit as a typed option, constant or port owned by one side.

## Speculative Abstraction

- **Shows as**: a components view whose ports have exactly one implementation, no test substitute and
  no plausible second provider; or layers that only forward calls.
- **Evidence**: interface-to-implementation counts; test usage of each interface; pass-through
  methods.
- **Cost**: indirection without benefit; navigation and review take longer.
- **Not a smell when**: the port isolates an external system, enables a test substitute, or is part
  of a published contract.
- **Response**: inline the abstraction. This is the counterweight to the other smells; do not
  recommend new ports without a stated benefit.

## Orphan Component

- **Shows as**: a component with no incoming edge from any entry point.
- **Evidence**: no registration, no route, no caller; feature flags that are never enabled.
- **Cost**: maintenance and review effort on unused code.
- **Not a smell when**: it is wired through a configuration-selected role or plugin discovery that the
  views did not show; fix the view in that case.
- **Response**: delete it, following the forward-only maintenance rules.

## Unmappable Structure

- **Shows as**: the components view cannot be drawn with fewer than about fifteen boxes without
  arbitrary grouping, or every box connects to most others.
- **Evidence**: the attempts made while drawing and why each grouping failed.
- **Cost**: there is no modular structure to reason about; every change is a whole-system change.
- **Not a smell when**: the container is genuinely simple and a components view adds nothing.
- **Response**: agree a target components view first, then realign incrementally, one component at a
  time, starting with the one changed most often.
