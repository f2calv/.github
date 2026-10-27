# Data Model: Packaging Inventory Preview

In-memory/output records, not new authored metadata or persisted releases. The
[command contract](contracts/inventory-preview.md) owns invocation and serialization.

## Source Snapshot

- `SourceCommit`: Full resolved commit object ID; do not assume a fixed hash length.
- `ValidationRules`: Literal `invoked-tool-bundle`, separate from source content revision.
- Internal tree entries: repository-relative path, type, Git mode and object ID.
- Internal inputs: committed raw defaults, sidecars, internal files, declarations and ignore rules.

One snapshot supplies every declaration/file. Trusted tooling is a separate authority, not payload
execution. Staged, unstaged, ignored-local and untracked bytes never substitute for committed input.

## Selection

- `Roots`: Unique native folder names, ordinally sorted; omission expands to all opted-in roots.
- `OptionalSelections`: Explicit `component-id/selectionKey` identifiers, sorted after validation.
- Internal requests preserve duplicates until validation rejects repeated optionals.

Reuse validation for identity, exact pins, required cycles, selected optional cycles and reachability.
Repeated roots are equivalent to one root; repeated optionals are invalid.

## Included Component

- `Id`, `Version`: Validated stable identity and exact declared version.
- `NativeFolder`, `Entrypoint`, `SourceCommit`: Derived committed source location and attribution.
- `RootIds`: Every selected root ID reaching this component, unique and ordinally sorted.
- `Reasons`: Every root or active incoming required/selected-optional edge reason.
- `License`: `Value`, `SourcePath`, `Field` and `Origin` (`repository-default` or `component`).
- `Notices`: Every effective path with declaration source, field/index and origin.

An edge reason records `FromId`, `ToId`, `Kind`, `SourcePath`, `Field`, and `SelectionKey` only
for optional edges. A root reason identifies its selected native folder. Together with root sets,
these explain diamonds without enumerating all paths. Membership is exactly validator `SelectedIds`;
output component order is ordinal by ID, not hash-table, caller or directory order.

## Inventory Entry

- `Path`, `SourceCommit`: Unique exact repository-relative path and chosen commit.
- `Mode`: Source regular-file mode (`100644`/`100755`). Binary content is not serialized.
- `Owners`: Every including component ID, unique and ordinally sorted.
- `Reasons`: Distinct attribution tuples, never reduced to one arbitrary category.

Each reason has `ComponentId`, `Kind`, `SourcePath` and `Field`. `Kind` is one of
`internal-content`, `external-instruction`, `external-notice`, `inherited-notice`, or
`component-notice`. Internal content refers to its owning native folder with `Field` equal to
`implicit-directory`. External reasons retain `LoadingPurpose` and declaration kind. Array
declarations use zero-based element indexes. Sort reasons by component, kind, source path and
field, with loading purpose as a final tie-breaker.

A file may be internal content of one component and external content of another: keep both reasons.
Deduplication does not permit declarations rejected by validation. Case collisions fail; do not
silently fold, resolve symlinks or rewrite paths.

## Preview Outcome

Success contains `SourceCommit`, `ValidationRules`, `Roots`, `OptionalSelections`, `Components`,
`Files` and `Limitations`. Collections remain arrays. Limitations state that local changes are
excluded and this is not a package, release record, rights clearance or delivery approval. No
payload bytes, timestamps, digests or durable catalog are generated.

Failure contains no success inventory. Sanitized categories distinguish prerequisites, source,
validation/selection, eligibility, inspection and cleanup. The contract owns exit behavior.

## Lifecycle

1. Request -> resolve snapshot and capture trusted rules.
2. Snapshot -> inspect safe paths and materialize inert validation data outside the repository.
3. Data -> validate complete catalog and selected closure; retain raw declaration attribution.
4. Validated closure -> evaluate snapshot ignore eligibility and construct ordered result.
5. Constructed result -> remove all temporary contexts -> emit success.
6. Any failure -> attempt cleanup -> emit categorized failure without partial success.

Nothing persists between invocations. Cleanup errors suppress success and state that operator
cleanup may be required, without exposing source contents or credentials in diagnostics.
