# Layered Modules in One Process

A synthetic catalog application owns product details. An ordering module needs a product quote
but must not update catalog rows directly. Both modules run in one host and release image.
This is a dependency-design example, not a compiled fixture or an instruction to split every
application into these projects.

## Allowed Reference Graph

An existing multi-project application could express these boundaries:

| Project | Allowed direct project references | Responsibility |
| --- | --- | --- |
| `Example.Catalog.Contracts` | None | Consumer-facing quote request/result contracts |
| `Example.Catalog.Application` | Catalog contracts | Quote rules and application-owned persistence port |
| `Example.Catalog.Postgres` | Catalog application and contracts | EF implementation of that persistence port |
| `Example.Ordering.Application` | Catalog contracts | Order workflow consuming the quote contract |
| `Example.Host` | Module application/adapter projects | DI composition, role selection and transport wiring |

The catalog application's project might contain:

```xml
<ItemGroup>
  <ProjectReference Include="..\Example.Catalog.Contracts\Example.Catalog.Contracts.csproj" />
</ItemGroup>
```

Its PostgreSQL adapter points inward to the application, not the reverse:

```xml
<ItemGroup>
  <ProjectReference Include="..\Example.Catalog.Application\Example.Catalog.Application.csproj" />
  <ProjectReference Include="..\Example.Catalog.Contracts\Example.Catalog.Contracts.csproj" />
</ItemGroup>
```

These are fragments, not complete project manifests. EF/provider package references belong in the
adapter according to the application's existing package management. The host registers the
adapter against the application-owned port; the application contains no `UseNpgsql` call.

The consumer-facing quote contract might return product ID, price, currency and version. It must
not return an EF entity, `DbContext`, provider connection or deferred `IQueryable`. Ordering uses
the quote result and its own rules; it cannot change catalog state through that result.

## Logical Layers, Not Three Deployment Tiers

The request travels through HTTP transport, application policy and the database adapter inside
one process. That is logical layering. Splitting these projects does not create independently
running presentation/application/data-service tiers.

The persistence port illustrates ports/adapters: the application defines the behavior it needs,
and the PostgreSQL implementation depends on that contract. This does not make every interface a
port or require adding interfaces to single-implementation internal helpers.

For a single-assembly application, preserve the same ownership through namespaces, internal
visibility and focused review/tests. Project-reference checks alone cannot enforce those
boundaries, and namespace naming alone does not prevent a forbidden call.

## Cross-Module Consistency

A synchronous quote call is appropriate when ordering needs an immediate result. The returned
version documents what was quoted; it does not make quote retrieval and order submission atomic.
Define revalidation/reservation policy if correctness depends on the product changing between them.

Do not replace this call with a global event bus just to remove a visible reference. If independent
role deployments require cross-process communication, an in-process call or event no longer
connects them; choose the actual transport and failure contract explicitly.

## Boundary Acceptance Cases

| Check | Expected evidence |
| --- | --- |
| Catalog application references PostgreSQL adapter | Rejected by the application's dependency check/review; composition belongs in the host |
| Ordering imports catalog EF entities | Rejected, even if a transitive package reference makes it compile |
| Contracts expose `IQueryable` or provider types | API/dependency review detects the leak before downstream coupling |
| Host wires a fake catalog port in an isolated test | Application behavior can be tested without opening a database |
| Adapter uses the application's port | Matching implementation and registration are verified; declaring an interface alone is insufficient |
| Selected role lacks a required catalog dependency | Startup validation identifies the unsupported composition rather than failing on the first request |
| Single-assembly layout | Symbol/namespace-level checks or explicit call review supplement project checks |

Use the repository's existing test/analyzer tools with execution approval. These cases specify
what to verify; no architecture enforcement or runtime success has been executed by this example.
