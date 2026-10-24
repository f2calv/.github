---
name: dotnet-efcore
description: 'Design, implement, audit and troubleshoot Entity Framework Core data access, DbContext lifetimes and factories, entity mappings, PostgreSQL/Npgsql, LINQ query performance, tracking, tenant isolation, transactions, concurrency, raw SQL, seeding, migrations and rolling schema deployments. Use for EF Core work beyond package bumps, including model drift, provider-backed tests and database/cache consistency.'
argument-hint: '[audit|model|query|migration|diagnose] [path or context]'
user-invocable: true
---

# EF Core Data Access

Centralize reusable EF Core knowledge without turning one application's persistence choices into
universal architecture. Follow the real provider, model and transaction boundaries before changing
code; verify generated SQL and database behavior rather than trusting LINQ or a passing build alone.

## Authorities and Progressive Loading

| Concern | Authority |
| --- | --- |
| Mapping and schema-safety invariants | [EF Core instructions](../../instructions/dotnet.efcore.instructions.md) |
| Lifetimes, factories, provider setup, mappings and tenancy | [Contexts and models](./references/contexts-and-models.md) |
| Read shapes, tracking, performance, writes, concurrency, SQL and cache boundaries | [Queries and writes](./references/queries-and-writes.md) |
| Scaffolding, seeding, expand/contract, deployment and provider-backed validation | [Migrations and validation](./references/migrations-and-validation.md) |
| Configuration and credentials | [Configuration instructions](../../instructions/dotnet.configuration.instructions.md) |
| Test structure and execution approval | [Testing instructions](../../instructions/dotnet.testing.instructions.md) |
| Redis cache implementation and invalidation | [Redis data access](../redis-data-access/SKILL.md) |
| Major-version release research and package propagation | [.NET upgrade](../dotnet-upgrade/SKILL.md), [.NET release train](../dotnet-release-train/SKILL.md) |

Load only the relevant references. Keep MCP/HTTP authorization and output contracts, deployment
orchestration, general C# style and test-runner mechanics in their owning instructions/skills.
This skill owns EF-specific procedures, not a second copy of those rules.

## Modes and Safety Boundaries

- `audit`: inspect and report without edits or database execution.
- `model`, `query`, `migration`: implement the requested change and directly related wiring,
  documentation and test code. Confirm ambiguous schema, transaction or public-contract choices.
- `diagnose`: trace a reported symptom to its query, provider, lifetime, schema or concurrency
  cause. Start with source and existing sanitized evidence.
- Scope to the named repository/context/feature. Follow existing shared helpers before adding a
  repository abstraction, custom unit of work, upsert framework or parallel persistence path.
- A code request is not permission to connect to a live database, apply migrations/backfills,
  create/drop databases, inspect application rows, run `EXPLAIN ANALYZE`, or deploy. Ask for the
  exact environment and operation before such actions. Even diagnostic queries can expose data,
  acquire locks or execute writes.
- Ask before builds and tests, including EF CLI operations that build or initialize the host.
  Inspect design-time startup first: apparently offline EF commands can start hosted services,
  access secrets or execute application initialization.
- Never print resolved connection strings, SQL parameter values, tenant identifiers or record
  contents. Keep sensitive-data logging disabled in shared environments; use synthetic examples
  and sanitized diagnostics. A provider exception can itself contain sensitive values.

## Workflow

### 1. Map the Existing Persistence Boundary

1. Read repository notes and scoped instructions; inspect worktree changes without overwriting
   unrelated work. Identify actual projects, EF/runtime/provider/design/tool versions, supported
   TFMs and database server capabilities. Verify compatibility instead of matching version numbers.
2. Trace DI registration, context/factory creation, model configuration, stores/services, callers,
   migration assembly/snapshot, design-time creation, schema application, seed paths and tests.
   Record each configured context and provider; an unused `DbSet` or design document is not proof
   of a working persistence path.
3. Establish the unit of work, who disposes it, who calls `SaveChanges`, tenancy/authorization,
   read/write ownership, consistency requirements and source of truth. Distinguish scoped contexts,
   context factories, context pooling and driver connection pooling.
4. Identify external schema deployment, current application/schema compatibility, raw SQL that
   depends on the model, and caches or event publishers affected by commits. Keep private
   repository provenance local; publish only generic lessons in this central skill.

### 2. Select the Smallest Correct Change

| Work | Establish before editing |
| --- | --- |
| New entity or mapping | Nullability, keys, relationships/delete behavior, lengths/precision, provider types, indexes and how existing rows are handled |
| New read | Authorized scope, required fields, stable ordering, bounds, consistency and whether entities must be tracked |
| Slow query | Actual SQL shape, round trips, returned rows/columns, existing indexes and a representative baseline |
| Write or race | Database-enforced invariant, expected competing writers, atomicity, conflict result and retry/idempotency policy |
| Schema change | Current snapshot, deployed migration state, old/new application overlap, data volume, locks, backfill and recovery plan |
| Test | Behavior that needs the production provider, isolation/cleanup ownership, credentials and execution approval |

Explain material alternatives before implementing them. Prefer a normal scoped context for a
request-sized unit of work; use a factory for independently scoped operations or long-lived
services. Neither pooling, no-tracking, split queries nor compiled queries is a blanket upgrade.

### 3. Implement Through the Existing Boundaries

1. Apply the relevant reference's procedure and the provider's current documentation. Keep domain
   policy in the owning application service; controllers, components and tooling should not grow
   a parallel database access path.
2. Wire registrations, runtime and design-time configuration consistently. Preserve provider
   conditions and existing schema names; a mapping refactor can be a destructive schema change.
3. When a model changes, scaffold a migration and inspect its SQL/data operations using the
   migration reference. Do not rewrite published migration history to conceal a model change.
4. Preserve cancellation, async disposal, tenant scope, exception translation, concurrency
   semantics and transaction ownership. Do not catch a database error and return empty data or
   success, and do not translate every `DbUpdateException` into a duplicate-record conflict.
5. Update affected tests and documentation in the same change. Record deferred work at the owning
   declaration or in a scoped issue, with the constraint and revisit trigger rather than a
   speculative persistence roadmap.

### 4. Verify the Exact Contract

With approval, select only the checks required by the change:

- Build affected solutions/configurations/retained TFMs, including published-package paths when
  local project substitutions differ.
- Check model/snapshot drift and inspect generated migrations and SQL before producing deployable
  artifacts. A migration file's presence does not establish model consistency or deployment safety.
- Test query translation, constraints, JSON/provider types, transactions and races against an
  isolated instance of the production database engine where those semantics matter. SQLite and
  EF InMemory are not PostgreSQL substitutes.
- Verify old and new application compatibility with the expanded schema, fresh initialization and
  upgrade of existing data. Schema rollback and application rollback are separate operations.
- For performance changes, compare the claimed metric with representative data and equivalent
  conditions; verify result correctness as well as latency, allocations, query count or row volume.
- Exercise authorization, duplicate writes, stale revisions, cancellation and failure paths when
  touched. Prove all mutating paths maintain the same invariant, including bulk SQL.

Report concrete files/symbols, the invariant or query shape changed, validation performed and
remaining deployment/backfill/operator steps. Separate code verification from checks declined or
blocked by credentials/infrastructure. Never present an empty database, successful restore or
mocked provider test as proof of production correctness.

## Maintaining This Skill

- Revisit guidance when EF Core, `dotnet-ef`, Npgsql or the database server changes its supported
  versions, query translation, JSON/complex-type mapping, concurrency or migration behavior.
  Use the upgrade skill for release-specific highlights rather than embedding a second release log.
- Recheck CLI options, design-time startup, migration locking, seeding invocation and deployment
  runner behavior against the actual tool/provider version before use.
- Watch migration designer/snapshot size and indirect `HasData` sources during use; evolve the
  seed-payload gate when new ways of embedding or overwriting runtime-owned data are discovered.
- Fold new reusable implementation lessons into the matching reference; preserve application
  policies and private provenance in their own repositories. A single implementation is evidence,
  not a reason to mandate its factory, lock or cache architecture everywhere.
- Keep invariants in the scoped instruction file and procedures here. Amend or move the existing
  authority rather than duplicating migration, query, cache or test guidance across skills.
