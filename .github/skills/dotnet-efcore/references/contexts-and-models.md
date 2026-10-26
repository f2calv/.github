# Contexts and Models

## Context Lifetime and Registration

- Treat a context as one short-lived unit of work, not a singleton, application cache or shared
  connection. Await each operation before reusing it; never run concurrent queries on one context.
  A context invalidated by an EF programming error should not be reused.
- `AddDbContext<T>` suits a request-sized scope. `IDbContextFactory<T>` suits background/singleton
  services, independently scoped operations and UI lifetimes that outlive a unit of work.
  Factory-created contexts are caller-owned: use `await using` and pass cancellation to async work.
- When several operations must share tracking or a transaction, keep them within one explicitly
  owned unit of work. Creating a new factory context for each method can accidentally split it.
  Do not return an unexecuted `IQueryable` or async stream after disposing its context.
- Context pooling and connection pooling solve different problems. Introduce context pooling only
  with evidence and verified state reset: per-request tenant state, interceptors, open connections
  and session state must not leak to the next borrower. `OnConfiguring` is not per-request setup.
- Resolve configuration through the application's established options/provider chain; never
  hardcode or log connection strings. Keep application registration and the design-time factory
  aligned on provider, naming, schema, extensions and migration assembly without starting workers.
- Choose a provider compatible with the actual EF and database versions. Keep EF runtime/design
  packages on a compatible release line and use the repository's tool manifest/central package
  management; do not automatically install a global latest `dotnet-ef`.

Official guidance:
[context configuration](https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/),
[pooling and state](https://learn.microsoft.com/en-us/ef/core/performance/advanced-performance-topics),
[design-time creation](https://learn.microsoft.com/en-us/ef/core/cli/dbcontext-creation),
[Npgsql provider](https://www.npgsql.org/efcore/).

## Model Changes

1. Inspect the current model configuration and snapshot together. Reuse the established inline
   `OnModelCreating` or `IEntityTypeConfiguration<T>` organization; do not split or rename every
   mapping as part of an unrelated feature. Follow the scoped naming invariants before scaffolding.
2. Set deliberate keys, unique/alternate keys, foreign keys, requiredness, delete behavior,
   string lengths, numeric precision and generated values/defaults. A required CLR member is not
   a database default, and a client-side validation check is not a database constraint.
3. Design indexes around actual filter, join and ordering shapes, including tenant scope and a
   unique pagination tie-breaker. Avoid indexing every property; verify write overhead and plans.
   Provider-specific filtered/expression/JSON indexes require provider/server support.
4. Preserve provider semantics for UTC timestamps, decimals, enums, JSON/JSONB, complex or owned
   types and conversions. Verify round trips and translated predicates before changing a type or
   converter. Do not assume SQL Server `rowversion`, schemas or JSON behavior exists elsewhere.
5. Inspect `Include`, relationship fixup, cascade deletes and serializers when changing navigation
   properties. Do not expose tracked entity graphs as external contracts accidentally.
6. Treat schema/naming-convention switches as migrations, not formatter changes. Compare table,
   column, index and constraint names to the existing database; generate and review the diff.

Official guidance:
[modeling](https://learn.microsoft.com/en-us/ef/core/modeling/),
[indexes](https://learn.microsoft.com/en-us/ef/core/modeling/indexes),
[Npgsql type mapping](https://www.npgsql.org/efcore/mapping/general.html).

## Tenant Scope and Authorization

- Derive the effective tenant/scope from the trusted application boundary and apply it before
  materializing. A caller-supplied identifier is a filter, not authorization.
- Scope reads, updates, deletes, alternate/unique keys and cache keys consistently. A globally
  unique row ID alone does not establish that the caller may read or mutate it.
- Global query filters can provide default tenant/soft-delete predicates, but do not enforce
  write authorization. Inspect `IgnoreQueryFilters`, attached/disconnected entities, raw SQL,
  bulk operations and administrative paths separately.
- A filter using tenant state must read the correct context-instance state, not a model-building
  constant captured from the first tenant. Verify model-cache and pooling behavior before
  introducing dynamic schemas or pooled tenant contexts.
- Required navigations and global filters can alter result cardinality through joins. Test
  tenant/soft-delete combinations on the real provider, not only the happy-path entity query.
- Do not project sensitive columns and redact later when a server-side safe projection can avoid
  loading them. Keep domain-specific disclosure/retention rules in their owning API/tool workflow.

Official guidance:
[global query filters](https://learn.microsoft.com/en-us/ef/core/querying/filters),
[multi-tenancy](https://learn.microsoft.com/en-us/ef/core/miscellaneous/multitenancy).
