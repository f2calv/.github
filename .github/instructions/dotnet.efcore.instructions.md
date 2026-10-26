---
description: 'EF Core and PostgreSQL invariants for model naming, schema safety and rolling compatibility; the dotnet-efcore skill owns implementation and migration workflows.'
applyTo: '**/*DbContext*.cs,**/*EntityTypeConfiguration*.cs,**/Entities/**/*.cs,**/Migrations/**/*.cs'
---

# EF Core And PostgreSQL

Use the [EF Core data-access skill](../skills/dotnet-efcore/SKILL.md) for context lifetimes,
factories, mappings, queries, performance, transactions, concurrency, migrations, seeding and
provider-backed validation. This file owns the scoped invariants; the skill owns their procedures.

## PostgreSQL Naming

- Use `snake_case` for every PostgreSQL table, column, index, constraint and sequence identifier.
- Follow the repository's established mapping strategy consistently: configure a snake-case naming
  convention globally, or map identifiers explicitly with APIs such as `ToTable`, `HasColumnName`
  and `HasDatabaseName`. Never rely on CLR type or property names to produce PostgreSQL identifiers.
- In a repository that uses explicit mappings, add the mapping before generating a migration.
  Review the migration and model snapshot for accidental PascalCase identifiers before committing.

## Model and Migration Safety

- A context is a short-lived, single unit of work, never shared concurrently. Keep read/write tenant
  scope and database constraints authoritative even when using query filters, raw SQL or caches.
- Scaffold migrations from the current model build and review generated code, SQL and snapshot.
  Never rewrite published/applied migration history or remove a migration with unknown deployment
  state. An unexpectedly empty migration requires investigation.
- Keep large, mutable and runtime-owned data out of `HasData`. Removing model-managed seed data
  is a potentially destructive data migration, not a metadata-only change.
- Reject new migration, designer and snapshot changes dominated by embedded datasets. Loading
  data from a helper, file or generator and passing it to `HasData` still embeds it in the model.
  Use an explicit idempotent seeding path outside the model; reserve `HasData` for a small,
  genuinely static reference set whose inclusion is justified during review.
- Gate CI and deployment artifact publication on the current model's
  `dotnet ef migrations has-pending-model-changes` check. Stop on missing migrations before
  publishing artifacts or mutating deployment manifests.

## Shared Schema and Rolling Compatibility

- Apply schema changes through an external, serialized, reviewable migration step that completes
  before application rollout. Disable migrate-on-startup in shared environments; local development
  may use it deliberately. Keep schema-changing privileges separate from the runtime identity.
- Preserve compatibility with every application version still running or supported for rollback.
  Use expand/migrate/contract across releases: additive structures first, compatible writes and
  backfill next, destructive changes only in a later release after old dependencies are gone.
- New columns must be nullable or have a database default compatible with old writers. Renames,
  drops, type narrowing and non-null tightening cannot accompany the first code switch.
- Preserve old/new representations during the transition where rollback requires dual writes;
  validate backfill completion and concurrent writers before contract.
- Deployment retries must be safe for the actual provider and runner. Migration-history checks do
  not make arbitrary DDL or data operations idempotent after partial failure.
