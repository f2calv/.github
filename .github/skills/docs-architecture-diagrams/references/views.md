# View Catalogue

Rules and templates for each view in the [architecture diagrams skill](../SKILL.md). Templates use
synthetic names; replace every element with one verified in source. Styling classes and shapes come
from the [Mermaid conventions](./mermaid-conventions.md).

## Contents

- [System Context](#system-context)
- [Containers](#containers)
- [Components](#components)
- [Runtime Scenario](#runtime-scenario)
- [Activity Flow](#activity-flow)
- [Lifecycle](#lifecycle)
- [Dependency Graph](#dependency-graph)
- [Code Map](#code-map)
- [Native C4 Syntax](#native-c4-syntax)

## System Context

The system is one opaque box. Show every kind of person and external system that sends it input or
receives its output, and nothing inside it.

- One element for the system, styled `system`. Its label states what it is in a few words.
- People and calling applications as stadiums on the left; external dependencies on the right.
- Label every edge with what flows and how: `submits orders, HTTPS`, `publishes events, AMQP`.
  Direction follows the request or the data, whichever the reader cares about; be consistent.
- Group external systems only when several share an owner and a protocol.
- Omit infrastructure that is invisible to the system's behavior, such as a load balancer.

```mermaid
flowchart LR
    classDef system fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
    classDef person fill:#ede9fe,stroke:#6d28d9,color:#2e1065
    classDef external fill:#fef3c7,stroke:#d97706,color:#78350f

    customer([Customer]):::person -->|places orders, HTTPS| orders[Order service<br/>accepts and fulfils orders]:::system
    operator([Operator]):::person -->|manages catalogue, admin UI| orders
    orders -->|charges cards, HTTPS| payments[Payment provider]:::external
    orders -->|sends receipts, SMTP| mail[Email service]:::external
    idp[Identity provider]:::external -.->|issues tokens| customer
```

## Containers

Open the system box. A container is anything that runs as its own process or stores data on its own:
an API host, a worker, a scheduled job, a browser or mobile client, a database, a cache, a queue.

- Draw the system boundary as a subgraph labelled with the system name from the context view.
- Keep the people and external systems from the context view, with the same identifiers and styles,
  and re-attach each of their edges to the container that actually handles it.
- Label each container with its name and technology: `API host<br/>ASP.NET Core`.
- Data stores the system owns sit inside the boundary as cylinders, labelled with what they hold.
- A configuration-selected role of one image becomes its own container only when it is deployed
  separately; otherwise mention the roles in the container label.
- Libraries and NuGet or npm packages are not containers; they belong in the dependency graph.

```mermaid
flowchart LR
    classDef container fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
    classDef store fill:#e5e7eb,stroke:#4b5563,color:#111827
    classDef person fill:#ede9fe,stroke:#6d28d9,color:#2e1065
    classDef external fill:#fef3c7,stroke:#d97706,color:#78350f

    customer([Customer]):::person -->|HTTPS| web
    subgraph orders [Order service]
        web[Web client<br/>browser SPA]:::container -->|JSON over HTTPS| api[API host<br/>ASP.NET Core]:::container
        worker[Fulfilment worker<br/>.NET worker]:::container
        db[(Orders database<br/>PostgreSQL)]:::store
        queue[(Order events<br/>queue)]:::store
        api -->|reads and writes| db
        api -->|publishes| queue
        queue -->|consumes| worker
        worker -->|updates status| db
    end
    api -->|HTTPS| payments[Payment provider]:::external
    worker -->|SMTP| mail[Email service]:::external
```

## Components

Open one container. A component is a cohesive responsibility behind a small public surface: a group
of types that change together and are used through a few interfaces. It is not a class, a folder or a
technical layer, although a well-structured codebase makes each component one folder or project.

- One view per container; title the subgraph with the container name from the containers view.
- Five to twelve components. Name each by responsibility (`Pricing`, `Fulfilment`), not by layer
  (`Services`, `Helpers`, `Managers`).
- Put the provided interfaces in the label: `Pricing<br/>IPriceCalculator`. Name a port only when it
  is used across a component boundary.
- Label edges with the required port when the target provides more than one.
- Inbound adapters (controllers, consumers, MCP tools) form one component per protocol at the top.
  Outbound adapters may be shown as their own components when several components share them.
- Show the elements outside the container that components touch, with their established styles.
- A component the container registers from a package but does not implement, such as a shared
  pipeline library, stays in the view when it carries runtime behavior. Style it `published`, add a
  legend line, and name the package in the code map's location column.
- Draw only dependencies that exist in code. Missing expected edges and surprising extra ones are
  both findings for the report.

```mermaid
flowchart TB
    classDef component fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
    classDef store fill:#e5e7eb,stroke:#4b5563,color:#111827
    classDef external fill:#fef3c7,stroke:#d97706,color:#78350f

    subgraph api [API host]
        http[HTTP endpoints]:::component
        ordering[Ordering<br/>IOrderService]:::component
        pricing[Pricing<br/>IPriceCalculator]:::component
        catalogue[Catalogue<br/>ICatalogue]:::component
        billing[Billing<br/>IPaymentGateway]:::component
        http --> ordering
        http --> catalogue
        ordering --> pricing
        ordering --> billing
        pricing --> catalogue
    end
    ordering -->|IOrderRepository| db[(Orders database)]:::store
    billing -->|HTTPS| payments[Payment provider]:::external
```

## Runtime Scenario

One use case end to end, in time order. Use it when the order of collaboration, an asynchronous
hand-off or a failure path is the point.

- Participants are containers or components from the static views, with the same names. Declare them
  in left-to-right order of first involvement, actors first.
- Label messages with the port operation or protocol message (`IOrderService.Place`, `POST /orders`),
  not private method chains.
- Use `autonumber`. Use `alt` and `else` for the significant failure, `opt` for conditional steps,
  `par` for concurrency and `loop` for retries or batches. Prefer one important failure path to
  exhaustive error handling.
- Show asynchronous messages with `-)` and replies with `-->>`.
- Aim for fifteen messages or fewer. Split a longer scenario at a natural hand-off.

```mermaid
sequenceDiagram
    autonumber
    actor Customer
    participant http as HTTP endpoints
    participant ordering as Ordering
    participant billing as Billing
    participant db as Orders database
    participant payments as Payment provider

    Customer->>http: POST /orders
    http->>ordering: IOrderService.Place
    ordering->>db: save pending order
    ordering->>billing: IPaymentGateway.Charge
    billing->>payments: create charge
    alt charge accepted
        payments-->>billing: approved
        ordering->>db: mark paid
        http-->>Customer: 201 Created
    else charge declined
        payments-->>billing: declined
        ordering->>db: mark rejected
        http-->>Customer: 402 Payment Required
    end
```

## Activity Flow

A process with steps, decisions and hand-offs between owners: an ingestion pipeline, an approval
workflow, a build and release flow. Use it when branching matters more than timing.

- Start and end nodes are stadiums. Decisions are diamonds whose outgoing edges are labelled with the
  outcome. Steps are verb phrases.
- Use subgraphs as swimlanes for the component, container or role that owns each step.
- Show loops back explicitly with a labelled edge rather than duplicating steps.
- Mermaid has no fork and join bar. Show parallel branches as edges from one step that rejoin at a
  step labelled with the join condition.

```mermaid
flowchart TD
    classDef terminal fill:#dcfce7,stroke:#15803d,color:#14532d
    classDef failure fill:#fee2e2,stroke:#b91c1c,color:#7f1d1d

    start([Order paid]):::terminal --> reserve
    subgraph warehouse [Fulfilment worker]
        reserve[Reserve stock] --> available{In stock?}
        available -->|yes| pick[Create pick list]
        available -->|no| backorder[Mark backordered]
        backorder -->|stock arrives| reserve
    end
    subgraph notify [Notifications]
        pick --> receipt[Send dispatch email]
    end
    receipt --> done([Order dispatched]):::terminal
    backorder -->|cancelled after 30 days| cancelled([Order cancelled]):::failure
```

## Lifecycle

The states one entity, job or session can occupy, and the events that move it. Use it when a status
column or enum drives behavior across several components.

- Derive states from the enum or status values in code; derive transitions from the code that sets
  them. Never invent intermediate states.
- Label transitions with the triggering event or operation.
- Mark terminal states with transitions to `[*]`.

```mermaid
stateDiagram-v2
    [*] --> Pending: order placed
    Pending --> Paid: charge approved
    Pending --> Rejected: charge declined
    Paid --> Dispatched: pick list completed
    Paid --> Backordered: stock unavailable
    Backordered --> Paid: stock reserved
    Backordered --> Cancelled: timeout elapsed
    Dispatched --> [*]
    Rejected --> [*]
    Cancelled --> [*]
```

## Dependency Graph

Which build units reference which. Generate it from manifests: project files, package manifests,
module files or chart dependencies. Never draw it from memory.

- Edges point from the dependent to its dependency, labelled only when the kind of reference differs
  (`project`, `package`, `build-only`).
- Group by layer or deployable with subgraphs; style owned units differently from external packages.
- Exclude test projects unless the graph exists to explain test topology.
- Include external packages only when they define an important boundary, such as a provider SDK.
- A cycle, or an edge pointing from a core unit to an adapter or user interface, is a finding.

```mermaid
graph TD
    classDef owned fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
    classDef published fill:#dcfce7,stroke:#15803d,color:#14532d
    classDef external fill:#fef3c7,stroke:#d97706,color:#78350f

    host[Orders.Host]:::owned --> app[Orders.Application]:::owned
    host --> infra[Orders.Infrastructure]:::owned
    infra --> app
    app --> contracts[Orders.Contracts]:::published
    client[Orders.Client]:::published --> contracts
    infra --> sdk[Payment SDK]:::external
```

## Code Map

The bridge from diagrams to source. It is a table, not a diagram, and lives under `## Code Map` in the
drilldown next to the components view it describes.

| Component | Responsibility | Code location | Provides | Requires |
| --- | --- | --- | --- | --- |
| Ordering | Accepts, validates and tracks orders | `src/Orders.Application/Ordering/` | `IOrderService` | `IPriceCalculator`, `IPaymentGateway`, `IOrderRepository` |
| Pricing | Calculates order totals and discounts | `src/Orders.Application/Pricing/` | `IPriceCalculator` | `ICatalogue` |

- One row per component in the components view, in the same order.
- Code location uses folders, namespaces or file-name patterns that a reader can glob. When a
  component is scattered, list every location; the scatter is itself a finding.
- Provides and Requires list ports, endpoints or protocols, never concrete classes.

## Native C4 Syntax

Mermaid's `C4Context`, `C4Container` and `C4Component` diagrams, and the `architecture-beta`
diagram, are experimental. Their layout is hard to control, styling differs between renderers and
syntax may change. Use `flowchart` with the conventions above unless the repository already uses
native C4 diagrams and every renderer its readers use has been verified.
