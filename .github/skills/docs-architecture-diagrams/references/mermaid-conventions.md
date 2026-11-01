# Mermaid Conventions

Syntax, styling and heading conventions for every Mermaid diagram, used by the
[architecture diagrams skill](../SKILL.md). Choose the diagram type that matches the relationship,
not the technology; the [view catalogue](./views.md) maps each question to a type.

## Diagram Types

| Type | Use for | Direction |
| --- | --- | --- |
| `flowchart` | Context, containers and components; sequential processes such as data, event, build and deployment flows | `LR` for context, containers and wide pipelines; `TB` or `TD` for components and vertical flows |
| `graph` | Non-sequential relationships: dependencies, references and hierarchies | `TD` for dependency trees, `LR` for peer relationships |
| `sequenceDiagram` | Time-ordered interactions: calls, asynchronous hand-offs and timing | Not applicable |
| `stateDiagram-v2` | Lifecycles of one entity, job or session | Not applicable |
| `classDiagram` | Published extension-point hierarchies only: inheritance (`<\|--`), composition (`*--`), aggregation (`o--`), association (`-->`) and dependency (`..>`) | Not applicable |

## Standard Headings

Use these headings before a diagram so readers and agents find the same view in the same place.

| Heading | Use For |
| --- | --- |
| `## System Context` | The system as a black box with its people and external systems |
| `## Containers` | Separately running or storing units and their communication |
| `## Components` | Responsibilities inside one container; use `## <Container> Components` when a document holds several |
| `## Code Map` | The component-to-source table beside a components view |
| `## Runtime Scenarios` | Sequence diagrams, one `###` subsection per scenario |
| `## Data Flow` | How data moves through the system |
| `## Event Flow` | Event-driven processing: publish/subscribe, channels and streams |
| `## <Process> Activity` | One process or pipeline with decisions and hand-offs |
| `## <Entity> Lifecycle` | States of one entity, job or session |
| `## Dependency Graph` | Package, module, project and chart dependencies and references |
| `## Deployment Flow` | Build, release and deployment pipelines, and their call chains |
| `## Configuration Hierarchy` | Nested configuration objects |
| `## Class Hierarchy` | A published extension-point type hierarchy |

A legacy `## Service Architecture` heading usually holds a System Context or Containers view; rename
it to the matching heading when the diagram is next updated.

Under each heading, write one or two sentences stating what the reader should notice before the
diagram, and add a legend line when colors or line styles carry meaning.

## Shapes

| Shape | Syntax | Meaning |
| --- | --- | --- |
| Rectangle | `id[Label]` | Systems, containers, components, steps and jobs |
| Stadium | `id([Label])` | People and calling applications; start and end of a flow; top-level reusable units |
| Cylinder | `id[(Label)]` | Databases, caches, queues, storage and state backends |
| Diamond | `id{Label}` | Decisions |
| Circle | `id((Label))` | Events |

Solid arrows (`-->`) are synchronous calls or hard references; dotted arrows (`-.->`) are
asynchronous, optional or indirect relationships. Keep that meaning consistent within a document.

## Styling

Define colors with `classDef`, never with `style` on individual nodes, so a category is styled once.
Set explicit fill, stroke and text colors so the diagram stays readable in light and dark themes.
Reuse this palette across every view of a system so a category keeps its color at every zoom level:

```text
classDef system    fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
classDef container fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
classDef component fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
classDef owned     fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
classDef published fill:#dcfce7,stroke:#15803d,color:#14532d
classDef store     fill:#e5e7eb,stroke:#4b5563,color:#111827
classDef person    fill:#ede9fe,stroke:#6d28d9,color:#2e1065
classDef external  fill:#fef3c7,stroke:#d97706,color:#78350f
classDef terminal  fill:#dcfce7,stroke:#15803d,color:#14532d
classDef failure   fill:#fee2e2,stroke:#b91c1c,color:#7f1d1d
```

Declare only the classes a diagram uses. Do not rely on color alone: labels, shapes or line styles
must carry any distinction a reader needs, such as current versus planned.

## Syntax Rules

- Use stable lowercase identifiers and put the display name in the label: `ordering[Ordering]`. Keep
  an element's identifier identical across every view.
- Quote labels containing parentheses, brackets, colons, slashes or other punctuation:
  `api["API host (ASP.NET Core)"]`.
- Use `<br/>` for line breaks inside labels. Keep labels to two short lines.
- Never use `end` as a node identifier in a flowchart; it closes a subgraph. Avoid identifiers that
  start with `o` or `x` directly after an arrow, which Mermaid reads as edge markers.
- Declare a subgraph with an identifier and label: `subgraph api [API host]`.
- Do not use `click`, `%%{init}%%` theme overrides or HTML beyond `<br/>`; renderers handle them
  inconsistently.
- Keep a diagram to about fifteen nodes. Split by zoom level or by concern before adding more.

## Rendering

GitHub and VS Code render Mermaid, usually lagging the latest Mermaid release. Package registries
such as NuGet do not render it; a README published there must explain essential usage in prose.

When Node.js is available, render each diagram before publishing. Extract the blocks to `.mmd` files
in a temporary folder outside the repository, give that folder its own `package.json`, and install
the CLI there with its browser dependency, because older npm versions neither resolve scoped
packages through `npx -p` nor install peer dependencies:

```powershell
'{"private":true}' | Set-Content package.json
npm install @mermaid-js/mermaid-cli puppeteer
./node_modules/.bin/mmdc -q -i diagram.mmd -o diagram.svg
```

Rendering to PNG with `-b white -s 1.5` gives an image that can be viewed to check layout, not just
syntax. The install downloads a headless browser; ask before running it on a metered or restricted
host. A parse error names the line; fix it and re-render. Delete the temporary folder afterwards.
When rendering is not possible, say so in the report.
