---
description: 'EF Core migrations — expand/contract (parallel change) convention for zero-downtime rolling deployments.'
applyTo: '**/Migrations/**/*.cs'
---

# EF Core Migrations — Expand/Contract (Parallel Change)

When an application runs rolling `Deployment` updates against a shared database, the old and new ReplicaSets hit the **same** schema simultaneously. Every migration MUST be backward-compatible with the currently-running release — follow the expand/contract (parallel change) pattern.

- **Schema application is external, not in-pod.** Apply migrations from a dedicated step that runs to completion **before** the new ReplicaSet rolls — an idempotent EF SQL script (`dotnet ef migrations script --idempotent`), an `efbundle`, or a one-shot migration workload gated behind a deploy hook (e.g. an Argo **PreSync Job**). Disable automatic migrate-on-startup in shared environments so no pod races to migrate at boot. Runtime `MigrateAsync()` is inappropriate for production (instance races, elevated schema perms, no inspection step, hard rollback). Local development may keep migrate-on-startup for convenience.
- **Additive-only within a release.** A single release may only ADD tables, columns, indexes, or constraints that older code ignores. New columns are added **nullable** (or with a DB default). Never add a NOT NULL column without a default while older pods are still running.
- **Never rename or drop in the same release as the code change.** A rename spans **two** releases: expand (add the new column) → migrate (dual-write and backfill, ship code that reads the new column) → contract (drop the old column). Dropping a column/table follows the same split: stop referencing it in release N, drop it in release N+1.
- **Nullable → backfill → non-null across releases.** (1) Add the nullable column plus code that writes it; (2) backfill existing rows (migration data step or a job); (3) once all rows are populated **and** no old pods remain, a later release adds the NOT NULL constraint and/or drops the legacy column.
- **Dual-write during migrate.** While both old and new columns exist, new code writes **both**, so a rollback to the previous release still functions.
- **Destructive DDL only after contract.** Column/table drops, type narrowing, and NOT NULL tightening land only once no running pod references the old shape.
- **CI guards.** Run `dotnet ef migrations has-pending-model-changes` in CI to fail on model/migration drift. Review the generated SQL before merge — a "rename" can silently become a drop + add (data loss). Migrations must be idempotent and re-runnable.
- **Deploy-hook + rolling interaction.** The external migrator applies the EXPAND (additive) schema → the rolling `Deployment` brings up new pods that tolerate both the old and new shape → old pods drain. Only a subsequent release's migrator runs the CONTRACT.

## References

- [EF Core — Applying Migrations](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying)
- [EF Core — Managing Migrations (`has-pending-model-changes`)](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/managing)
- [Martin Fowler — Parallel Change (expand/contract)](https://martinfowler.com/bliki/ParallelChange.html)
