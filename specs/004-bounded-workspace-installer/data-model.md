# Data Model: Bounded Workspace Installer

**Status**: Proposed `skill-workspace-install/1` generated evidence; no new authored metadata schema.
The existing dependency graph remains authoritative, and Spec Kit retains the installation registry.

## Selection

| Field | Type | Rule |
| --- | --- | --- |
| SourceCommit | Full Git object ID | Resolve once from SourceRevision; read committed bytes only |
| Root | Component identity | Exactly one ID, literal version and native folder from validated metadata |
| OptionalSelection | Sorted unique selection keys | Existing `id/selectionKey` semantics; no inferred selections |
| ActiveComponents | Validated component identities | Combined closure resolved by the existing validator |
| ExtensionRoots | Ordered component identities | Root first, distinct selected optional targets sorted by ID; at most 16 |
| RequiredInventories | Per-root inventory | Resolve each root with no optional selections at SourceCommit |
| Tools | Tool identity records | Participating script/schema hashes and runtime/interpreter identity |

An optional offer has declaring component ID, selection key, target ID/version/native folder, declared
reason, sidecar path, optional-array index and selected flag. Offers are exposed only from active
components. Selecting one may expose additional offers; those stay unselected. Repeated target IDs
produce one extension root with all declared inclusion reasons, not multiple installations.

Required inventory records retain source path, Git mode, byte length, SHA-256 and inclusion reasons.
No returned record points to inventory-owned temporary files after inspection cleanup. Invalid pins,
cycles, missing versions or inactive/unknown selection keys block readiness.

## Local Artifact

| Field | Type | Rule |
| --- | --- | --- |
| RootId / Version | Strings | Literal equality with the required inventory and catalog record |
| Catalog | Local path, size, SHA-256, entry key | Existing generated JSON shape; one unambiguous selected record |
| CatalogUrl | String | Provenance only; never dereferenced by this increment |
| Archive | Local path, size, SHA-256 | One candidate under explicitly supplied artifact directories |
| BuildEvidence | Existing extension-build record | Contract, source archive digest, commit, root and Spec Kit version agree |
| SourceManifest | Existing native archive manifest | Required-only membership and source identities match committed inventory |
| Members | Ordered regular-file records | Relative name, mode, size, hash and purpose; no links or unexpected members |
| RuntimeManifest | Existing extension manifest | Exact identity/version, runtime requirement and command-only profile |
| Command | Command ID and source member | One `speckit.<id>.load` command using the generated loading command |

The candidate filename is not identity evidence. Reject missing/duplicate candidates, duplicate
JSON/YAML keys, extra capabilities, unsupported archive entries, traversal, digest mismatches, missing
notices and incomplete source evidence. Enforce at most 64 MiB per archive and uncompressed payload,
16 MiB per member and 16 extensions. Reject member modes that upstream would change relative to the
canonical manifest. No build, download or fallback can repair a blocked preview.

## Consumer Snapshot

The snapshot records the canonical absolute workspace location and device/inode identity, initialized
runtime version, interpreter/module hashes, Copilot skills-mode settings and trusted integration
identity. Each inspected managed path records absence or type, device/inode identity, mode and, for
files, size/hash. Ancestors are checked component by component; links and ambiguous ownership block.

Include runtime registry/configuration, init options, integration settings/manifests, prospective
payload/command paths, operation namespace/lock state and the script paths upstream may chmod. Preserve
existing unrelated registry entries and modes. The snapshot is a bounded precondition set plus the
runtime's known traversal/write surface, not a claim that the entire filesystem is sandboxed.

An existing extension directory, registered ID, prospective command path or orphaned ownership blocks
even when its version/hash matches. Corrupt registration/configuration is a blocker, not empty state.
An existing operation namespace needs a valid tool-owned format marker; missing ownership cannot be
adopted. Completed receipts remain evidence, never authority to accept an occupied runtime target.

## Preview And Conflicts

| Field | Type | Rule |
| --- | --- | --- |
| Contract / Mode | Strings | `skill-workspace-install/1` and `preview` |
| Ready | Boolean | True only when every required input/precondition is available and valid |
| Blockers | Conflict array | Stable code, scope, safe explanation, observed/expected evidence |
| Selection / OptionalOffers | Detached records | Complete choices, declared reasons and exact pins |
| Extensions | Ordered artifact/install records | Per-extension payload, provenance, command and intended paths |
| Overlaps | Resource overlap records | Source path/hash and owning extension IDs; no physical deduplication |
| ConsumerSnapshot | Snapshot | Approval-relevant state, including absence and unresolved operations |
| IntendedWrites | Ordered path/effect records | Payload, registration, command and operation-owned scratch/evidence |
| Fingerprint | SHA-256 or null | Lowercase digest of the canonical approval projection; null if blocked |

Canonical fingerprint encoding is UTF-8 compact JSON, object keys sorted ordinally and arrays ordered
by their defined keys. Hash source/tool/runtime identity, selections/reasons, catalog origins/bytes,
selected artifact/member evidence, workspace identity, inspected state and predicted mutations.
Exclude presentation order, timestamps and ephemeral invocation details. Derive the operation directory
from the ready fingerprint so its exact paths can be previewed; exclude its own derived directory name
from the hashed projection to avoid self-reference. A fingerprint is freshness evidence, not a secret
or a permission token. A blocked or stale preview cannot authorize writes.

### Fingerprint Ordering

Normalize only the generated approval projection; never rewrite source, catalog, manifest or archive
bytes. Compare strings case-sensitively by their UTF-8 bytes, without Unicode normalization or
culture-dependent collation. Compare integer indexes numerically and composite keys left to right.
Object keys use that same string comparison. Canonical JSON uses UTF-8 without a BOM or trailing
newline, no insignificant whitespace, literal non-ASCII characters, standard JSON escaping for quotes,
backslashes and controls, lowercase booleans/null and decimal integers without leading zeros. Preserve
mode strings and digests as strings; reject unsupported numeric/non-JSON values rather than coercing
them. Keep modeled nulls and empty arrays distinct.

| Projection Collection | Primary Ordering Key |
| --- | --- |
| OptionalSelection and other unordered string lists | Exact string value |
| ExtensionRoots and Extensions | Requested root first, then distinct optional root IDs |
| ActiveComponents and components within RequiredInventories | Component ID |
| RequiredInventories | Owning extension's position in ExtensionRoots |
| Tools | Role, then canonical absolute Path; each tool record supplies both strings |
| Catalog and artifact input origins | Canonical absolute path, then catalog entry key where present |
| OptionalOffers | Declaring component ID, selection key, then numeric optional-array index |
| Inventory files, archive Members, Overlaps and snapshot path records | Exact source/member/workspace-relative path as appropriate |
| IntendedWrites | Workspace-relative path, owning extension's execution position if present, then effect |
| Inclusion reasons and any other unordered evidence records | Complete recursively canonical JSON bytes |

Within an equal primary key, use the complete recursively canonical record bytes as the final
tie-breaker, sorting nested arrays by these same rules first. Required identity/path uniqueness checks
still reject conflicting or duplicate records; sorting must not hide them. Preserve authored array
positions as explicit numeric declaration indexes in reasons/offers, not as incidental enumeration
order. Any additional sequence whose order affects execution must carry an explicit numeric position
and sort by it before the byte tie-breaker; do not infer execution order from discovery order.

Semantically identical permutations of unordered input arguments or discovered records produce the
same fingerprint. Changing a bound value, authored declaration index or execution position changes
the projection. Exact catalog/artifact byte changes still invalidate approval even if their parsed
meaning is equivalent, because their raw digests remain bound.

Conflict codes distinguish Selection, Prerequisite, Catalog, Artifact, Workspace, Ownership,
CommandConflict, OperationState, ApprovalMismatch, RuntimeFailure and VerificationFailure. Stable codes
support automation; explanations must not dump credentials, full configuration or third-party content.

## Operation Evidence

Tool-owned evidence lives in the consumer under the exact namespace in the
[command contract](./contracts/workspace-install.md). It contains a format marker and one operation
directory per reviewed fingerprint, not a list that replaces Spec Kit registration.

| Field | Type | Rule |
| --- | --- | --- |
| Contract / OperationId | Strings | Generated format and approved fingerprint |
| ReviewedFingerprint / ApprovedInputs | Digest and detached evidence | Exact recomputed preview; no secret environment values |
| State | Operation state | Prepared, Running, Completed, Failed, Cancelled or Unknown |
| Extensions | Per-extension outcomes | Pending, Attempting, Verified, Failed or Unknown |
| IntendedPaths / ObservedPaths | Path/effect records | Before/after identities, modes/hashes and verification findings |
| RecoveryLocations | Paths | Retained evidence, scratch and ambiguous runtime targets |
| LastDurableStep | Identifier | Progress written before each upstream call and after verification |

Write and flush the approved operation before the first runtime call. Mark an extension Attempting
durably before delegation. Mark Verified only after checking resources/notices, generated command,
literal version, registration and preservation of unaffected state. A successful upstream return
without these checks is not Verified. Receipt-write failure also stops the operation.

## State Transitions

| Current State | Event | Next State | Required Effect |
| --- | --- | --- | --- |
| Preview | Any blocker | Blocked | Report, no consumer writes |
| Ready preview | Changed inputs or mismatched approval | Blocked | New preview/approval required, no runtime call |
| Ready preview | Matching explicit apply | Prepared | Reserve owned namespace/lock, persist approval |
| Prepared / Running | Begin extension | Running / Attempting | Persist intent before runtime call |
| Attempting | Complete and verify | Running / Verified | Persist observed results before next extension |
| Running | Every extension Verified | Completed | Flush final evidence, release owned lock |
| Prepared / Running | Failure or cancellation | Failed / Cancelled | Stop; retain completed and partial state |
| Any unfinished operation | Missing outcome, torn evidence or lost process | Unknown | Preserve evidence; block another apply |

Verified earlier extensions remain Verified if a later one fails. A failed runtime call may have
written files, so retain observed paths and mark uncertain portions Unknown rather than claiming no
change. Hard termination may leave Prepared/Running/Attempting on disk; a subsequent invocation treats
these as unresolved. No automatic transition from an unresolved state to a fresh apply exists.

Maintainer reconciliation preserves the old operation record outside the active operation namespace,
inspects runtime-owned state and removes only deliberately confirmed disposable leftovers using
separately approved runtime/manual operations. The tool has no reconcile/delete/force switch. A new
preview must establish clean targets; retained completed installations continue to block reapplication.
