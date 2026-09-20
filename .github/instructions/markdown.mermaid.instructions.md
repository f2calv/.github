---
description: 'Mermaid diagram selection, headings, styling and synchronization conventions for Markdown documentation.'
applyTo: '**/*.md'
---

# Mermaid Diagrams

Use Mermaid diagrams in `README.md` files to visualise complex relationships and flows. Choose the
diagram type that matches the relationship, not the technology.

## Diagram Type Selection

- **`flowchart`**: sequential processes — data flow, event flow, orchestration, build and deployment pipelines.
  - Direction: `TD` for vertical flows, `LR` for wide pipelines.
- **`graph`**: non-sequential relationships — dependencies, references, hierarchies.
  - Direction: `TD` for dependency trees, `LR` for peer relationships.
- **`classDiagram`**: type hierarchies — inheritance (`<|--`), composition (`*--`), aggregation (`o--`), association (`-->`), dependency (`..>`).
- **`sequenceDiagram`**: time-ordered interactions between components — calls, asynchronous operations, timing.

## Standard Headings

Use these heading patterns before a diagram:

| Heading | Use For |
| --- | --- |
| `## Data Flow` | How data moves through the system |
| `## Event Flow` | Event-driven processing: publish/subscribe, channels, streams |
| `## Service Architecture` | How runtime components interact |
| `## Dependency Graph` | Package, module and project dependencies and references |
| `## Application Hierarchy` | Nested application or component structures |
| `## Class Hierarchy` | Type structures and inheritance trees |
| `## Deployment Flow` | Build, release and deployment pipelines, and their call chains |
| `## Configuration Hierarchy` | Nested configuration objects |

## Styling Guidelines

- **Subgraphs**: group related components, stages or layers.
- **Custom styling**: define `classDef` to distinguish categories that matter to the reader, such as components this repository owns versus external ones it only consumes.
- **Node shapes**:
  - `[ ]` rectangle (default) — components, jobs, steps
  - `([ ])` stadium — entry and exit points, reusable or top-level units
  - `[( )]` cylinder — databases, storage, state backends
  - `{ }` diamond — decision points
  - `(( ))` circle — events

## Synchronisation

- Diagrams must stay in sync with the code, configuration or pipeline they describe.
- When renaming a component, input or output, update the corresponding diagram nodes in the same change.
- When adding or removing a dependency, update the dependency graph in the same change.
- Review every `README.md` diagram before opening a pull request.
