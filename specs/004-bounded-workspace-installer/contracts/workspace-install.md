# Contract: Bounded Workspace Installation

**Status**: Proposed interface, not implemented. Contract identifier: `skill-workspace-install/1`.
Scope: Linux, one existing initialized built-in Copilot skills-mode workspace, Spec Kit CLI 1.2.3,
trusted committed source and explicitly approved local generated catalog/artifact files.

## PowerShell Surface

Planned entry point and function:

```text
.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1
Invoke-SkillWorkspaceInstall
```

| Parameter | Type / Default | Contract |
| --- | --- | --- |
| RepoRoot | Required absolute path | Existing source Git checkout; consumer must be outside it |
| SourceRevision | String, `HEAD` | Resolve to one commit; dirty working files never supply payload |
| SkillName | Required scalar string | Native skill folder selector already supported by inventory |
| OptionalSelection | String array, empty | Existing exact `id/selectionKey` values; explicit opt-in only |
| WorkspacePath | Required absolute path | Existing consumer root with compatible initialized integration |
| CatalogPath | Required absolute path array | Existing generated JSON catalogs; no URI fetch or trust setup |
| ArtifactDirectory | Required absolute path array | Existing trusted regular-directory roots containing selected ZIPs |
| PythonPath | Required absolute executable path | Existing interpreter with pinned runtime and YAML dependency |
| Apply | Switch, false | Omission means consumer-read-only preview |
| ReviewedFingerprint | String, absent | Required lowercase SHA-256 with Apply; otherwise rejected |
| Json | Switch, false | Script renders its single structured result as JSON instead of a PS object |

Resolve absolute paths without accepting dot/dot-dot ambiguity. Catalog/artifact inputs must be outside
managed destination trees, with no linked file or ancestor. Existing source/tool and interpreter
identities are recorded, not silently installed or reconfigured. Reject duplicate parameters/keys,
unsupported selections and more than 16 distinct extension roots. No force, latest, URL-download,
upgrade, resume, adoption, rollback, profile or hook-execution switch exists.

The function returns one detached result. The script's JSON mode writes only that result to stdout;
sanitized operational diagnostics go to stderr. Do not mix upstream console output into JSON. Preview
can return all independently discoverable blockers, but never speculate through unreadable metadata.

## Local Catalog Binding

Read the exact generated JSON catalog shape from the preceding extension adapter. For each selected
extension ID/version require one matching catalog entry with nonempty SHA-256, runtime requirement,
provided command and provenance URL. An ambiguous duplicate record fails instead of applying precedence.
Derive the candidate name using `<id>-<version>.zip`, search only supplied artifact directories and
require exactly one regular candidate. Do not open ZIPs for declined optional roots.

Cross-check selected archive bytes, extension manifest, existing build evidence and native source
manifest against the frozen required-only inventory. Inventory, not catalog relationships or filename,
owns dependencies. Require every payload byte/mode, inclusion reason and notice; reject unexpected
members or extension capabilities. A URL may remain in evidence, but is never downloaded or used to
infer another local path. Missing local content blocks without repair or rebuilding.

## Preview Result And Approval

Return the [preview model](../data-model.md#preview-and-conflicts), including all extension identities,
declared reasons, optional offers, overlaps, provenance, exact intended writes and inspected conflicts.
An incomplete preview has Ready false and Fingerprint null. It must not construct a manager that
creates runtime directories, write a lock/receipt/cache, extract files into the consumer, alter modes
or change profile state. Read selected ZIP members through bounded read-only archive APIs; preview
does not require extraction. Any inventory scratch remains in its existing source-tool boundary and
is cleaned by its owner, not placed in the consumer.

Apply accepts only original input parameters plus ReviewedFingerprint, never a caller-edited result
object. Recompute the entire preview from current files using the data model's
[fingerprint ordering](../data-model.md#fingerprint-ordering). Require Ready and exact digest equality.
Before reservation, reject unresolved prior-operation state, including incomplete/inconsistent
receipts, abandoned locks and Prepared/Running/Attempting intent. This guard is required in the
foundation and must already be active for the first root apply, not deferred to later recovery work.
Reserve the tool-owned lock, recheck all approval-relevant state excluding that declared owned lock,
and account only for previewed namespace/marker creation, then persist the operation before runtime
mutation. If revalidation fails, do not call upstream; report
any already-created operation/lock evidence accurately. Recheck each remaining target and the expected
state produced by earlier verified steps before proceeding. No approval authorizes external writers.

## Accepted Runtime Profile

Strictly parse registry, extension configuration, init options and integration settings/manifests;
malformed/duplicate-key input is not empty default state. Require pinned Copilot skills mode and the
built-in adapter. Reject external adapters and any project adapter bytes that differ from the installed
trusted built-in adapter. The fresh child process must not import project Python or search a caller
working directory for adapter code. Capture participating runtime module and adapter hashes.

Accept only the existing `skill-extension-pilot/1` output shape: exact extension ID/version, read-only
effect, `==1.2.3` requirement, one expected generated load command, build/source evidence and canonical
resources. Reject hooks, events, configuration templates, integration providers and extra declarations.
Require no configured extension hooks/events that this install could mutate. Existing unrelated
extensions may remain only when their registration and files can be preserved without collateral writes.

Manager installation can normalize executable bits in project script trees. Preflight every visited
path and mode; reject links, unreadable paths, unknown traversal or any change to existing unrelated
content/modes. Reject selected canonical modes that would be changed by upstream normalization rather
than silently accepting a new byte/mode contract. Missing prerequisites and API drift fail closed.

## Upstream Bridge

The planned Python bridge uses a fresh process with isolated imports and bytecode disabled (`-I -B`).
Set its process-local `TMPDIR` to the approved operation scratch before importing the runtime. No
environment/configuration change is persisted. Recheck artifact identity; hash/inspect/rewind one open
regular ZIP stream, then call the current upstream method:

```text
ExtensionManager(workspace).install_from_archive(
    archive_path, "1.2.3", priority=10, force=False,
    archive_file=stream, expected_id=id, expected_version=version)
```

Upstream owns extraction, payload copying and command/runtime registration. No local extraction
replacement, directory development links, compatibility-method alias, force operation or download
fallback is allowed. Literal canonical versions are checked independently of upstream semantic equality.
The command-only profile does not call CLI event refresh or config scaffolding; adding those capabilities
requires a separate contract change. Capture diagnostics without exposing configuration/secrets.

After return, verify all expected canonical resources/notices and modes, extension identity/version,
the generated Copilot skill through the pinned upstream renderer's expected output, and registry/config
state. Skipped command registration, compatibility warnings or incomplete evidence are failures, not
successful installation. Compare unrelated inspected state and record every observed approved change.

## Approved Mutation Set

The ready preview lists exact relative paths, preconditions and effects for:

```text
.specify/extensions/<id>/...
.specify/extensions/.registry
.specify/extensions.yml
.github/skills/speckit-<id>-load/SKILL.md
.specify/skill-library-install/owner.json
.specify/skill-library-install/lock
.specify/skill-library-install/operations/<fingerprint>/operation.json
.specify/skill-library-install/operations/<fingerprint>/scratch/...
```

Runtime-owned registry/config writes are allowed only as the exact structural additions predicted for
selected IDs; unrelated entries, comments/format and modes must remain unchanged, otherwise preflight
must reject that consumer. Parent directory creation and temporary evidence-write files are explicit
effects too. The full digest names the operation directory. Private extraction children beneath its
scratch directory may have runtime-generated names; approval covers that subtree only, not sibling paths.
Validate exclusive tool ownership before creating or replacing marker/receipt/lock state. Operation
directories are private mode 0700 and evidence/lock files mode 0600. Evidence writes use guarded
same-directory temporary replacement and flush; this is not multi-file
atomicity or a power-loss durability guarantee.

Do not invoke catalog management/fetch, event refresh or profile trust setup. No source-checkout,
profile, system-temp or unrelated workspace writes are authorized. Preview the runtime's actual write
surface, not merely this directory list; inability to predict it is a prerequisite blocker. A lock
coordinates this tool only and cannot make upstream or a stable workspace hostile-writer safe.

## Apply Outcomes And Recovery

Return Contract, Mode `apply`, State, ReviewedFingerprint, OperationPath, CompletedExtensions,
FailedExtensions, UnknownExtensions, PendingExtensions, ObservedPaths, Blockers and RecoveryLocations.
Only State Completed with every selected extension verified is overall success. Stop at the first
failure/cancellation; never retry the next extension, delete payloads, roll back completed extensions
or label uncertain writes as absent. Persist before-call and after-verification progress. If a final
receipt cannot be written, suppress total success and expose the last durable evidence path.

| Script Exit Code | Meaning |
| --- | --- |
| 0 | Ready preview, or completed and verified apply |
| 2 | Blocked preview, stale/missing approval or unmet prerequisite before operation reservation |
| 3 | Apply failed/cancelled or outcome unknown after operation reservation; inspect retained evidence |
| 4 | Unexpected internal failure; report whether mutation began and the last durable evidence path |

Missing/torn evidence, abandoned lock, Prepared/Running/Attempting state or inconsistent runtime results
block subsequent apply. Do not delete an ambiguous lock automatically. A maintainer must inspect and
preserve the record, reconcile runtime state deliberately and request a new preview. There is no
automatic reconciliation command. Existing verified extensions remain occupied targets, even if a
previous multi-extension operation failed later.

## Acceptance Boundaries

The proposed checks are in the [validation guide](../quickstart.md). Registration and installed bytes
are distinct from editor discovery/invocation. Require a separately observed native command invocation
and actual installed-only resource reads for editor acceptance; report owner observations separately
from independently captured traces. Artifact integrity does not authenticate a publisher or grant
redistribution rights. No command in this contract grants execution, testing or delivery approval.
