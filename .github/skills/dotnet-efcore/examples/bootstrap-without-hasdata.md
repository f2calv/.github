# Bootstrap Data Without Migration Payloads

A synthetic catalog has many initial product-category rows. Operators may edit their labels after
initialization. These are bootstrap defaults, not immutable model metadata.

## The Anti-Pattern

```csharp
modelBuilder.Entity<Category>().HasData(CategoryDefaults.All);
```

Even if `CategoryDefaults.All` reads JSON or assembles many small helper files, EF embeds its
returned rows in the snapshot and migration designers. A schema-only migration can then carry
another full target-model copy. Moving the rows to helpers does not reduce that generated payload.

## Separate Schema and Initialization

Keep only mappings and constraints in the model. For PostgreSQL, a reviewed schema might be:

```sql
CREATE TABLE categories (
    code text PRIMARY KEY,
    display_name text NOT NULL
);
```

This SQL is illustrative schema, not a replacement for generated/reviewed EF migrations. The
bootstrap dataset lives outside `OnModelCreating`, snapshots and migration metadata.

An initializer executes a parameterized command for each bounded batch:

```sql
INSERT INTO categories (code, display_name)
VALUES ($1, $2)
ON CONFLICT (code) DO NOTHING;
```

For synthetic inputs `("hardware", "Hardware")` and `("garden", "Garden")`, the primary key and
`ON CONFLICT` protect concurrent inserts. Existing labels survive reruns. There is deliberately
no `DO UPDATE` clause: this initializer does not own operator edits.

| Deployment path | Where initialization runs |
| --- | --- |
| EF CLI or migration bundle | A configured `UseSeeding` delegate; add the corresponding `UseAsyncSeeding` implementation for async migration paths. Verify the actual runner/version invokes it. |
| SQL migration script | A separate, explicitly ordered initializer after schema application; executing SQL does not invoke EF delegates. |
| Ongoing category synchronization | An application import with explicit update/deletion ownership, not `HasData` and not this insert-only bootstrap. |

Reuse the application's data-source/connection and seeding helpers. Do not create a new global
connection, put connection strings in commands, run from every replica opportunistically, or add
a custom seeding framework for this example. If initialization is required to serve requests,
its successful completion gates readiness.

## Transition From Existing Model-Managed Rows

1. Identify applied migrations and preserve them unchanged.
2. Add the initializer, with schema ordering and ownership above.
3. Remove the large `HasData` source and scaffold a **new** transition migration.
4. Inspect generated `DeleteData` and reverse operations. Remove/replace only those that would
   erase rows being transferred to the initializer; keep legitimate schema/data changes.
5. Verify that the new snapshot contains the schema but no bootstrap rows. Historical migration
   designers remain large unless a separately approved rebaseline is performed.

## Acceptance Cases

| Case | Required outcome |
| --- | --- |
| Fresh database | Schema applies, initializer creates both synthetic categories. |
| Second run | No duplicate rows or unintended updates. |
| Operator renamed `hardware` to `Tools` | The label remains `Tools` after initialization reruns. |
| Concurrent initializers | Exactly one row per code; no partial/unhandled duplicate conflict. |
| Upgrade from previous schema | Existing rows/relationships survive the transition migration. |
| Next schema-only migration | No repeated bootstrap payload in its designer or snapshot. |
| Initializer fails | Deployment/readiness reports failure rather than pretending empty data is success. |

These are cases to implement and run with approval against isolated PostgreSQL, not executed
results. Do not use EF InMemory to claim `ON CONFLICT` or migration correctness.
