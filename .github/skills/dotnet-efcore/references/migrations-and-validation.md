# Migrations and Validation

## Establish the Tooling and Deployment State

1. Identify the context, provider, migration assembly, startup project, tool manifest and snapshot.
   Verify the tool/runtime/provider combination and design-time factory before running commands.
   Use explicit project/startup/context arguments where selection would otherwise be ambiguous.
2. Determine which migrations are published/applied and which application versions can still
   run or roll back. Repository files alone do not establish the live database state; inspect it
   only with approval and the correct target. Never remove or rewrite deployed migration history.
3. Agree on schema/data effects, deployment owner, migration identity, locking/downtime constraints
   and rollback/recovery before changing a populated/shared database. Scaffolding and applying
   are separate actions.

### Remedy Older EF Tools Warnings

When EF reports that its tools are older than the runtime, resolve the mismatch rather than
repeatedly accepting or suppressing the warning:

1. From the repository root, inspect `dotnet ef --version`, the applicable local tool manifests,
   global/custom-path installation and the project's resolved EF Core runtime and Design packages.
   The installed global tool is not necessarily the tool the repository invokes.
2. Update the existing owning installation to the exact resolved EF Core runtime version when
   available. Stay on the project's supported release line; do not install an unqualified latest
   version, introduce a new manifest, upgrade application/provider packages or change SDK selection
   merely to remove the warning. If that version is unavailable or incompatible, report the
   blocker and agree a compatible version rather than silently proceeding.
3. Use `dotnet tool update dotnet-ef --tool-manifest <absolute-manifest-path> --version <version>`
   for a repository-local tool. For a global or custom-path installation, confirm the shared-machine
   impact before using `--global` or `--tool-path <absolute-tool-directory>` with the same explicit
   version. Preserve the existing installation scope; do not update unrelated tools.
4. Align directly related CI, container or setup pins that supply this repository's EF tool.
   Verify `dotnet ef --version` through the original invocation path, then repeat an approved
   offline model check or SQL-generation command and require the warning to disappear.
   Never rerun a live database update merely to verify tooling; build/test approvals still apply.

Record the old/new versions and changed pins. If updating is blocked or declined, state that
explicitly and obtain a decision before further migration work.

## Scaffold and Inspect

- Change the model/mapping first. Scaffold from current compiled code; let `migrations add` build
  by default. `--no-build` requires explicit verification that the assembly reflects this model.
  An unexpectedly empty `Up` or `Down` is a stale-build warning, not evidence of no schema change.
- Use a descriptive migration name. Retain generated metadata and the matching model snapshot;
  prefer the tooling over hand-authoring or editing the snapshot.
- Review `Up`, `Down` and generated SQL for data loss, accidental identifier changes, drop/add
  disguised as rename, missing defaults/backfills, index locks and provider-specific operations.
  A reverse `Down` migration cannot recover data erased by `Up`.
- Inspect `HasData` changes for unintended `InsertData`, `UpdateData` and `DeleteData` churn.
  Remove only demonstrable no-op generated operations, then verify the SQL and snapshot still
  represent the intended model. Do not hide a real data change by deleting its operation.
- Use `migrations remove` for an unpublished, confirmed-unapplied last migration, so files and
  snapshot revert together. For offline removal, verify the current tool's `--force` behavior:
  use it only after proving the migration is not deployed/applied. Never use it to bypass unknown
  deployment state; it can attempt database rollback when reachable.
- If design-time creation requires a connection string for an offline operation, use a clearly
  non-routable placeholder through the approved configuration path; never borrow a real endpoint
  or print credentials. Do not assume every EF command is offline.

## Kubernetes Migration Ownership

For applications deployed with multiple Kubernetes replicas, use one externally orchestrated,
finite migration Job:

1. Run the same immutable application image as the daemon workloads.
2. Select a dedicated `--migrate` mode before normal host role composition.
3. Register only configuration, the required provider/context factory and the application migrator.
4. Create an async DI scope, call `Database.MigrateAsync` with cancellation, dispose and exit.
5. Do not start HTTP listeners, background workers, subscriptions, schedulers or ordinary
   application initialization.
6. Require the relational provider and required connection configuration; an in-memory/no-op
   migration must fail rather than report success.
7. Make the migration role exclusive with daemon roles.
8. Disable application `MigrateOnStartup` behavior for ordinary pods.

Render this mode as one Kubernetes Job with no Service or probes. An Argo CD PreSync hook or
equivalent deployment gate should complete successfully before new daemon replicas roll out.
Do not use a migration init container on every replica: replica scaling and rollout overlap can
start concurrent migration owners, and init-container results are coupled to each pod rather than
one visible release operation.

Retain migration history in EF and immutable application releases. A failed Job blocks rollout;
application rollback and schema rollback remain separate decisions.
### Command Selection

These are CLI shapes, not permission to execute them. Supply the repository's actual
`--project`, `--startup-project`, `--context`, framework/configuration and output paths as needed.
Confirm options against the installed tool, and ask before implicit builds.

```text
dotnet ef migrations add <DescriptiveChange>
dotnet ef migrations has-pending-model-changes
dotnet ef migrations script --idempotent --output <reviewed-sql-path>
dotnet ef migrations bundle --output <bundle-path>
dotnet ef migrations remove
```

The pending-model check must use the current model build. Gate CI and deployment artifact
publication on model consistency before changing deployment manifests. Its success does not
prove that a migration has been applied or that an existing database matches the expected schema.

Official guidance:
[managing migrations](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/managing),
[CLI reference](https://learn.microsoft.com/en-us/ef/core/cli/dotnet).

## Seed and Bootstrap Data

`HasData` is model-managed data, not a general-purpose bootstrap mechanism. EF serializes its
values into the snapshot and migration target-model designers, even if the call reads from a
separate class, JSON file or generator. Splitting the source payload into helper files does not
solve migration growth. Replacing `InsertData` with a giant inline SQL string only moves the bloat.

### Choose an Explicit Seeding Path

| Actual execution path | Bootstrap approach |
| --- | --- |
| EF tooling or migration bundle | Prefer `UseSeeding` and the corresponding `UseAsyncSeeding` path for initial data, verifying the installed version's invocation behavior and migration locking. Current tools/bundles invoke the synchronous delegate; an async-only registration is insufficient. |
| SQL-only schema deployment | Run a separately owned, explicitly ordered idempotent initializer/job after the required schema exists. Executing the SQL script does not invoke EF seeding delegates. |
| Ongoing mutable reference-data import | Use a bounded application/import workflow with deliberate ownership and update rules, not model-managed data or a new schema migration for each dataset refresh. |

Keep bootstrap data/logic outside the EF model and generated migration artifacts. Use stable
natural keys, database uniqueness and provider-supported upserts/insert-if-missing behavior;
preserve runtime/user-owned columns. Do not overwrite user edits on each deployment or use an
unprotected read-then-insert check as the only uniqueness control. Define restart, concurrent-run
and partial-failure behavior; retain external schema ownership rather than seeding opportunistically
from every application replica.

Seeding may run when there are no new migrations and after a downgrade. Make it genuinely
idempotent, and verify required schema availability when downgrade execution is supported.
Never replace migration-based schema management with `EnsureCreated` just to trigger seeding.
If the application requires seeded data to serve requests, gate readiness on successful
initialization; do not infer success from an empty query or conceal failure behind repeated
reads that eventually return an apparently valid empty result.

### Mandatory Seed-Payload Review Gate

Before accepting generated artifacts:

1. Inventory every `HasData` call and follow indirect dataset sources. Classify each dataset as
   tiny static model-managed values, bootstrap defaults or ongoing runtime-owned data; require
   an explicit justification for the model-managed exception.
2. Inspect the migration **and its designer and model snapshot**. Compare added bytes/lines and
   repeated row payloads, not only the size of `Up`/`Down`. Report the actual growth and source
   dataset; no invented universal file-size limit can distinguish schema from embedded data.
3. Stop on bulk copied datasets or unrelated seed insert/update/delete churn. Correct the model
   ownership/seeding design and regenerate the unpublished migration; do not accept the output,
   suppress a large-file check, or exclude generated files from review.
4. Verify that a later schema-only change does not regenerate the bootstrap payload and that
   seed edits do not cause unrelated schema migration churn. Confirm clean initialization,
   repeated seeding, existing user edits and concurrent initialization behave correctly.

### Replacing Existing `HasData` Safely

1. Establish deployed migration state and data ownership. Preserve published migration history;
   a new seeding path prevents future duplication but does not shrink historical designers.
2. Introduce the external-to-model seeding path with explicit insert/update ownership and test
   reruns against both empty and already-populated databases.
3. Remove model-managed data and scaffold the transition. Inspect and deliberately neutralize
   or replace generated `DeleteData` operations that would erase rows now owned by the seeder.
   Review reverse-direction operations too; never blindly delete every data operation.
4. Verify preserved rows and relationships, runtime-owned values, fresh initialization and an
   upgrade from the previous schema. The new snapshot must no longer embed the large payload.
   Any separate history squash/rebaseline requires explicit approval and a deployment-state plan;
   never rewrite shipped migrations as an incidental cleanup.

Official guidance:
[data seeding](https://learn.microsoft.com/en-us/ef/core/modeling/data-seeding),
[deployment strategy and seeding](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying).

## Rolling Deployment: Expand, Migrate, Contract

Old and new instances share one schema during a rolling update. The scoped EF instructions own
the compatibility invariant; implement it as separate release steps:

| Phase | Schema and data | Application and recovery requirement |
| --- | --- | --- |
| Expand | Add new structures; new columns are nullable or have a DB default old writers can tolerate. Review new constraints/indexes for old-write compatibility and blocking. | Apply the reviewed expansion before rolling new instances. Old code must keep running against it. |
| Migrate | Introduce dual writes where needed, backfill existing rows with restartable bounded work, and validate completion. | New code tolerates the transition; old instances and rollback may still write the old representation. Reconcile those writes before switching reads. |
| Contract | Drop/rename old structures, narrow types or enforce non-null only after data validation and proof that no supported running/rollback version needs the old shape. | A later release removes obsolete structures. Do not contract in the release that first switches callers. |

For a rename, add the replacement first rather than using an immediate database rename while old
code still depends on the original. For deletion, stop all code references in release N and remove
the structure in a subsequent compatible release. Nullable/backfill/non-null follows the same
cross-release sequence.

Dual writes must preserve the existing invariant atomically where required. Backfills need a
concurrency strategy for writers changing rows during the run, explicit progress/restart rules and
validation; a one-time script with no race analysis is not a completed migration.

### External Schema Application

- Use the established dedicated migration step, reviewed SQL script, migration bundle or one-shot
  deployment hook. It must complete successfully before the new application rollout; do not add
  another schema owner alongside it. Follow the deployment skill for the actual orchestrator.
- Keep schema-changing privileges with the migrator rather than the ordinary runtime identity.
  Migration locking in newer EF versions does not remove rollout-compatibility, review or
  least-privilege requirements.
- Generate reviewable SQL from the same migration range even when deployment uses a bundle.
  Idempotent scripts consult migration history; this does not make every individual DDL/backfill
  statement safely rerunnable after partial failure. Verify provider transactions, nontransactional
  statements, runner serialization, retry behavior and migration-history handling.
- Disable migrate-on-startup in shared environments. Local development may use it deliberately,
  but local convenience is not a production deployment procedure.
- Ask separately before executing database updates, migration bundles, SQL or backfills. Preserve
  the approved target and artifact; failure stops rollout rather than triggering an improvised
  destructive repair or a different database target.

Official guidance:
[applying migrations](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying),
[parallel change](https://martinfowler.com/bliki/ParallelChange.html).

## Validation Matrix

Use the repository's existing tests/tools and obtain execution approval. Never start, reset, drop
or reuse a shared database just because a test fixture can.

| Change | Smallest meaningful evidence |
| --- | --- |
| Query/projection | Correct result shape and bounds, translated predicates/order, no unintended tracked graph, provider-specific semantics |
| Mapping/index/JSON | Round trips, null/default/precision behavior, constraints/index metadata and generated SQL on the actual provider |
| Transaction/concurrency | Independent contexts/connections with competing operations, deterministic conflict/row counts and lock cleanup on failure/cancellation |
| Migration | No pending model changes, reviewed SQL, clean database initialization and upgrade from a representative previous schema with data preserved |
| Expand/contract | Old and new code tolerate expanded schema, old-writer/backfill races resolved, contract prerequisites and rollback boundary established |
| Initialization/cache | Reruns preserve runtime-owned values; post-commit invalidation, stale revisions and unavailable-cache behavior preserve the chosen contract |
| Performance | Equal-correctness before/after results with representative volume, parameter distribution and equivalent environment |

- Prefer isolated disposable databases using the production engine for relational guarantees.
  Ensure cleanup targets only the resource the fixture created; use synthetic data and keep
  credentials in the existing secret-backed configuration path.
- SQLite tests can exercise limited application behavior, not PostgreSQL schemas, JSONB,
  advisory locks, translation, isolation or type semantics. EF InMemory is not a relational engine;
  mocked `DbSet` success does not establish SQL behavior.
- Separate credential-free unit tests from provider-backed integration tests. Follow the shared
  test platform, fixture, traits and skip conventions rather than inventing a second runner.
- Inspect performance without leaking parameter values or row content. Treat unavailable service
  checks as unverified and identify exactly what remains for the operator.

Official guidance:
[testing strategy](https://learn.microsoft.com/en-us/ef/core/testing/choosing-a-testing-strategy),
[testing against the database](https://learn.microsoft.com/en-us/ef/core/testing/testing-with-the-database).
