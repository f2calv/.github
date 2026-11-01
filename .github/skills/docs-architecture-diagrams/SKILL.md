---
name: docs-architecture-diagrams
description: 'Create, update, audit and explain Mermaid architecture diagrams that zoom from a black-box system context through containers to components, plus sequence, activity/flow, state and dependency-graph views. Use to understand an unfamiliar or convoluted codebase top-down, to decide which diagrams belong in a README versus a docs/ drilldown, to build a component-to-code map that guides refactoring, or to choose diagram types, headings, shapes and styling.'
argument-hint: 'mode={create|update|audit|explain} [scope=repository|container|project] [path=...]'
user-invocable: true
---

# Architecture Diagrams

Explain a system from the outside in. Each view answers one question at one level of zoom, and
names the same elements the same way at every level, so a reader can descend from "what does
this system do for whom" to "which folder implements that responsibility" without reading code.

The zoom levels follow the [C4 model](https://c4model.com/): System Context, Containers and
Components. Class-level diagrams are deliberately excluded from maintained documentation; they
change with every refactoring and obscure the structure the higher views exist to reveal. A
component view names the interfaces a component provides and requires, never its classes.

## Scope and Authorities

| Concern | Authority |
| --- | --- |
| View selection, README versus drilldown placement, workflow and code map | This skill |
| Each view's question, Mermaid type, rules and template | [View catalogue](./references/views.md) |
| Mermaid syntax, shapes, styling, headings and rendering limits | [Mermaid conventions](./references/mermaid-conventions.md) |
| Keeping diagrams synchronized with code during any change | [Mermaid instructions](../../instructions/markdown.mermaid.instructions.md) |
| Markdown structure, README content boundaries and linting | [Markdown instructions](../../instructions/markdown.instructions.md) |
| README section selection around a diagram | [README authoring](../docs-readme/SKILL.md) |
| Assessing architecture smells and planning a realignment | [Architecture review](../patterns-architecture-review/SKILL.md) |
| Recording a proposed target architecture | [ADR authoring](../docs-adr/SKILL.md) |
| Domain-specific diagram conventions | The domain's own instructions or skill, such as GitOps, Helm or Terraform |

## Modes

| Mode | Outcome |
| --- | --- |
| `create` | Write the missing views for the requested scope from verified source evidence |
| `update` | Re-derive existing views after a change and correct drift in diagrams and the code map |
| `audit` | Report missing, stale, misplaced or inconsistent diagrams without editing |
| `explain` | Build the views as a read-only deep dive into an unfamiliar codebase; write them to the session workspace unless the user asks for repository files |

`explain` is the onboarding mode. Use it when a team has inherited or grown a system whose
structure is not evident from a quick read. Deliver the views in order, pausing after the
System Context and Containers so the user can correct boundaries before components are drawn.

## The View Set

Select views by the question the reader has, not by diagram availability. Most systems need the
first three; add the others only where they answer a real question.

| View | Question it answers | Mermaid type |
| --- | --- | --- |
| System Context | What is this system, who uses it, and which external systems does it exchange data with? | `flowchart LR` |
| Containers | Which separately running or separately storing units make up the system, and how do they communicate? | `flowchart LR` with a boundary subgraph |
| Components | Inside one container, which cohesive responsibilities exist and through which interfaces do they depend on each other? | `flowchart TB` with a boundary subgraph |
| Runtime scenario | In what order do elements collaborate for one important use case, including its significant failure? | `sequenceDiagram` |
| Activity flow | Which steps, decisions and hand-offs make up one process or pipeline? | `flowchart TD`, with lanes as subgraphs |
| Lifecycle | Which states can one entity or job occupy and what moves it between them? | `stateDiagram-v2` |
| Dependency graph | Which projects, packages, modules or charts reference which, and is the direction sound? | `graph` |
| Code map | Where does each component live in the source tree, and which ports form its public surface? | Markdown table, not a diagram |

Class hierarchies are allowed only for a published extension point that consumers implement or
derive from, and then only in that library's README. Generate any other class diagram on demand
in conversation and discard it.

## Placement

A README is the front door; it shows the black box. Drilldowns live under `docs/`.

| Location | Diagrams |
| --- | --- |
| Root `README.md` of an application or service | One overview: the System Context. Add the Containers view only when it has six or fewer elements and replaces prose that would otherwise be longer. Link to the drilldown. |
| Root `README.md` of a library, Action, reusable workflow, chart or module | One diagram for the consumer's mental model: a dependency graph of published packages, an execution flow, or a chart dependency graph. No component internals. |
| Project `README.md` | Only a view scoped to that project: its own dependency graph, or a published extension-point class hierarchy. Link to the drilldown rather than repeating repository views. |
| `docs/architecture.md` | The drilldown: Containers, one Components view per non-trivial container, the Code Map, and links to topic documents. Move each Components view to `docs/architecture/<container>.md` once the file holds more than about five diagrams; keep `docs/architecture.md` as the index. |
| Topic documents under `docs/` | Runtime scenarios, activity flows and lifecycles for that topic. The drilldown links to them instead of duplicating them. |
| ADR | A proposed target view that differs from the current code. Documentation describes what exists; a target lives in the decision record until the code matches it. |

Never draw the same view in two places. When a README and a drilldown both need a view, the README
links to the drilldown.

## Workflow

### 1. Establish Scope

1. Resolve the mode, the repository or container in scope, and where the result goes. In `explain`
   mode default to the session workspace; in other modes the Placement table decides.
2. Inventory existing diagrams and the headings above them. Record their type, location and claims;
   they are hypotheses to verify, not evidence.
3. Read the repository's own instructions for domain diagram rules before drawing.

### 2. Gather Evidence

Derive every element and edge from source. Treat names in existing prose as leads only.

- **System boundary and actors**: inbound endpoints (controllers, routes, gRPC services, MCP tools,
  CLI verbs, message consumers), who authenticates to them, and outbound clients (HTTP client
  registrations, SDK packages, connection strings, broker subscriptions, configuration sections
  naming external endpoints).
- **Containers**: entry points and hosting (`Program`, AppHost, `Main`, `Dockerfile`, Compose
  services, Helm workloads, jobs, browser clients), runtime roles selected by configuration, and
  every data store with what it holds. One image running several roles is one container per role
  only when the roles are deployed separately.
- **Components**: dependency-injection registration groups, feature or module folders, namespaces,
  interfaces under `Abstractions`, controllers grouped by route, and clusters of file-name prefixes
  in flat folders. A flat `Services/` folder with recurring prefixes usually hides several components.
- **Edges**: constructor and method parameters of the main classes, interface usages, project
  references and message contracts. Label each edge with the port (interface) or protocol it uses.
- **Scenarios and flows**: trace one request or job end to end through the actual call sites.

Record anything that resists a clean boundary; it feeds the signals in step 6.

### 3. Draw Top-Down

Draw the views in order. Each level reuses the names, identifiers and styling classes of the level
above, and every element at one level must belong to exactly one element at the level above.

1. System Context: the system as a single box. If it cannot be described in one sentence, the scope
   is wrong.
2. Containers: one boundary per system, data stores inside it when the system owns them.
3. Components: one view per container that has non-trivial internal structure. Aim for five to
   twelve components. Fewer usually means the container is simple enough to stop; more usually means
   two levels are being mixed or a component should be split into its own view.
4. Runtime scenarios, activity flows and lifecycles: only for behavior a static view cannot convey.
   Participants and lanes use component or container names, never class names.
5. Dependency graph: generated from manifests, not memory.

Follow the [view catalogue](./references/views.md) for each view's rules and template, and the
[Mermaid conventions](./references/mermaid-conventions.md) for syntax and styling.

### 4. Build the Code Map

Under `## Code Map` in the drilldown, list each component from the Components view:

| Component | Responsibility | Code location | Provides | Requires |
| --- | --- | --- | --- | --- |
| `<Name in the diagram>` | One sentence | Folders, namespaces or file-name patterns | Public interfaces or endpoints | Ports of other components or external systems |

The code map is what makes a diagram actionable. A request such as "rearrange the code to match the
Components view" is answered by comparing this table's code locations with the boundaries the view
draws; the [architecture review](../patterns-architecture-review/SKILL.md) owns that realignment.

### 5. Verify

1. Every element and edge traces to source evidence. Remove anything that cannot.
2. Names, identifiers and classes agree across all views and the code map.
3. Each diagram has a heading from the conventions, one or two sentences on what to notice, and a
   legend when styling encodes meaning.
4. Render each diagram when tooling is available, as described in the conventions. Otherwise
   disclose that rendering was not verified.
5. Run the repository's Markdown linting through its pre-commit configuration.

### 6. Report

Report the views written or found stale, their locations, and the evidence behind any element
whose boundary was a judgement call.

Close every `create`, `update` and `explain` run with an **Architecture signals** section: at most
five concrete observations made while drawing, each with its evidence and the smell name from the
[architecture review catalogue](../patterns-architecture-review/references/smells.md). Present them
as signals worth discussing, not verdicts. When any exist, offer a full architecture review. Write
"no notable signals" when none were found, rather than omitting the section. Never change code
because of a signal.

## Maintaining This Skill

- Mermaid releases and the version GitHub renders: recheck experimental diagram types, such as the
  native C4 and architecture diagrams, before recommending them over `flowchart`.
- GitHub, VS Code and package-registry Mermaid rendering support, including dark-mode contrast.
- The Mermaid CLI package name, invocation and browser download behavior used for render checks.
- The C4 model's level definitions and terminology.
