# Tasks: Bounded Workspace Installer

**Input**: Current [specification](./spec.md), [plan](./plan.md), [research](./research.md),
[data model](./data-model.md), [command contract](./contracts/workspace-install.md) and
[validation guide](./quickstart.md).

**Status**: T001-T030 implemented through approved root-only apply. The approved focused workspace
suite passed 65 tests and the neighboring inventory regression passed 49, with zero failures/skips.
T031-T054 remain unstarted. Root apply has synthetic validation only; optional selection, full
fault/termination hardening and real-runtime/editor acceptance remain pending. Ruff/mypy checks
remain unverified because those tools are unavailable. No real install, commit or push was performed.

**Tests**: Included for the specification's independent tests, measured refusal/failure scenarios and
SC-006 demonstration, using the planned adjacent Pester suite. Author story tests first; obtain test
approval before demonstrating the expected failure, then implement and rerun after approval. An
unavailable interpreter or unapproved execution is blocked/unverified, not a passing or skipped gate.

**Organization**: Setup, foundation, US1 (P1), US2 (P2), US4 (P2), US3 (P3), then cross-cutting validation.
The P2 tie follows specification order. Minimum preservation, durable intent and stop-on-failure belong
in the foundation/root apply; US4 verifies and hardens them rather than enabling unsafe interim apply.

## Format And Paths

Every task uses `- [ ] Tnnn [P?] [USn?] Description with exact file path`. A `[P]` marker identifies only
the different-file pair/group stated in the parallel examples, after its prerequisites. Story labels
are present only in story phases. Tasks that touch the same file are serial, even across phases.

Runtime additions stay inside the existing skill-library tool bundle; no new project, dependency
framework, authored metadata schema or runtime registry is created. Existing helpers/fixtures are reused.
Planned files may not exist yet; their paths below name implementation destinations, not completed work.

```text
.github/skills/skill-library/
  SKILL.md
  scripts/
    Invoke-WorkspaceInstall.ps1
    Invoke-SpecKitInstall.py
    Invoke-InventoryPreview.ps1
    Invoke-Tests.ps1
    tests/Invoke-WorkspaceInstall.Tests.ps1
```

Read applicable owning instructions/skills before future source edits. Tests, real artifact builds,
disposable consumer creation/use and editor demonstrations retain their separate approval gates. Do
not install prerequisites, create another checkout, host catalogs, commit or push as an implicit task
side effect. Phase-boundary commits, when separately authorized, follow the shared workflow authority.

## Phase 1: Setup

**Purpose**: Establish the existing-bundle entry points and synthetic harness without runtime mutation.

- [X] T001 [P] Add the shared synthetic fixture/harness scaffold in `.github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1`, reusing neighboring Git, archive and extension fixtures; prepare one root, required resources/notices, two optional peers, a nested offer and overlap, plus armed install/network/profile-write spies; fixture creation runs only within later approved tests.
- [X] T002 [P] Define the dot-source-safe `Invoke-SkillWorkspaceInstall` function and script boundary in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` with every parameter/default from the contract, required absolute source/workspace/catalog/artifact/interpreter paths, scalar SkillName, preview by default and fail-closed unsupported apply until implemented; preserve the host process when dot-sourced.
- [X] T003 [P] Define the isolated bridge's structured read-only inspection/apply request and response boundary in `.github/skills/skill-library/scripts/Invoke-SpecKitInstall.py`, keeping one machine-readable stdout result, sanitized stderr and explicit stage/outcome/error evidence; default inspection must not instantiate a mutating manager, extract payloads, execute project adapters or provision tools.

**Checkpoint**: No newly reachable operation can install or mutate a consumer; harness execution remains
unapproved until requested. T001-T003 can be authored independently against the saved contract.

## Phase 2: Foundational

**Purpose**: Complete shared selection, identity, ownership and evidence primitives before any story.

- [X] T004 [P] Add a detached internal committed-selection projection beside inventory internals in `.github/skills/skill-library/scripts/Invoke-InventoryPreview.ps1`, preserving its public preview shape and cleanup owner; enforce SourceCommit "Resolve once from SourceRevision; read committed bytes only", Root "Exactly one ID, literal version and native folder from validated metadata", ActiveComponents "Combined closure resolved by the existing validator" and Tools "Participating script/schema hashes and runtime/interpreter identity"; retain file paths, Git modes, byte lengths, hashes and attribution without scratch-backed references or executing historical tools.
- [X] T005 [P] Implement shared detached result/conflict constructors in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` for Contract/Mode `skill-workspace-install/1` and `preview`, Blockers "Stable code, scope, safe explanation, observed/expected evidence" and array-preserving empty/singleton results; restrict codes to "Selection, Prerequisite, Catalog, Artifact, Workspace, Ownership, CommandConflict, OperationState, ApprovalMismatch, RuntimeFailure and VerificationFailure" without dumping secrets/configuration or third-party content.
- [X] T006 [P] Implement strict read-only prerequisite/runtime inspection in `.github/skills/skill-library/scripts/Invoke-SpecKitInstall.py` for Linux, the existing supported interpreter/YAML dependency, Spec Kit 1.2.3 and the current `install_from_archive` signature; reject duplicate/malformed JSON/YAML, incompatible init settings, external adapters, changed project Copilot adapter bytes, hooks/events/config templates and unknown integration effects; capture installed module/adapter hashes before any mutating manager construction or project-code import.
- [X] T007 Implement reusable path, workspace and mode guards in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` using the contract's absolute-path/source-separation rules and Consumer Snapshot constraint "Ancestors are checked component by component; links and ambiguous ownership block"; inspect managed targets, registry/config, integration state and every script-tree path upstream may chmod, rejecting occupied exact-version/orphan targets, collateral mode changes, comments/format changes and unpredictable write surfaces; implement the read-only unresolved-operation guard here, blocking incomplete/inconsistent receipts, abandoned locks and Prepared/Running/Attempting intent before any reservation or root apply, without deleting evidence or adopting unknown ownership.
- [X] T008 Implement private owned namespace/lock and durable receipt primitives in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1`, callable only during apply, for the exact contract paths and modes 0700/0600; enforce Contract/OperationId "Generated format and approved fingerprint", ReviewedFingerprint/ApprovedInputs "Exact recomputed preview; no secret environment values", State "Prepared, Running, Completed, Failed, Cancelled or Unknown", per-extension outcomes "Pending, Attempting, Verified, Failed or Unknown", IntendedPaths/ObservedPaths "Before/after identities, modes/hashes and verification findings", RecoveryLocations "Retained evidence, scratch and ambiguous runtime targets" and LastDurableStep "Progress written before each upstream call and after verification"; use exclusive ownership checks and guarded same-directory flushed evidence replacement, never adoption or rollback.
- [X] T009 Implement common apply-result and failure/exit mapping in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` with all contract fields, exit 0 only for ready preview or fully verified completion, exit 2 before reservation for blockers, exit 3 for failed/cancelled/unknown reserved operations and exit 4 for unexpected failures; preserve last durable evidence and suppress success on evidence-write failure, reserving actual execution for later story wiring.

**Checkpoint**: Shared primitives are ready without changing the existing inventory API. Unknown
ownership, unsupported runtime effects and incomplete evidence fail closed. No story starts before
T004-T009 finish; these primitives are not acceptance evidence by themselves.

## Phase 3: User Story 1 - Review A Complete Installation Preview (P1)

**Goal**: Deliver a useful consumer-read-only root preview with exact provenance, optional offers,
intended paths, blockers and a reproducible approval fingerprint.

**Independent test**: Preview the synthetic root and compare its required-only inventory, declared
offers, identities, paths and conflicts to authoritative inputs. Consumer/profile bytes, modes,
registration and cache/receipt/lock state must remain unchanged, including blocked scenarios.

### Tests For US1

- [X] T010 [US1] Author preview contract tests first in `.github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1` for root-only success, all offers initially unselected, dirty/untracked source non-substitution, missing/duplicate catalog/artifact blockers, strict parsing, occupied/linked targets, unsupported runtime effects and zero consumer/profile/network/extraction writes; include every unresolved-operation case guarded by T007, asserting Ready false/Fingerprint null and unchanged evidence; assert armed spy counts and request test approval before recording the expected failing assertions.

### Implementation For US1

- [X] T011 [P] [US1] Implement bounded read-only selected-ZIP verification in `.github/skills/skill-library/scripts/Invoke-SpecKitInstall.py`, enforcing RootId/Version "Literal equality with the required inventory and catalog record", BuildEvidence "Contract, source archive digest, commit, root and Spec Kit version agree", SourceManifest "Required-only membership and source identities match committed inventory", Members "Relative name, mode, size, hash and purpose; no links or unexpected members" and RuntimeManifest "Exact identity/version, runtime requirement and command-only profile"; quote/enforce "64 MiB per archive and uncompressed payload, 16 MiB per member and 16 extensions", reject unsupported/traversing/duplicate entries and missing notices, and never extract or rebuild during preview.
- [X] T012 [US1] Predict command/registry/config and mode effects using the inspected pinned runtime in `.github/skills/skill-library/scripts/Invoke-SpecKitInstall.py`, enforcing Command "One `speckit.<id>.load` command using the generated loading command" and IntendedWrites "Payload, registration, command and operation-owned scratch/evidence"; derive expected Copilot rendered output without a mutating manager, reject skipped/unpredictable registration or serialization changes, and exclude event refresh, scaffolding, caches and profile trust writes.
- [X] T013 [P] [US1] Compose root selection and inactive optional offers from the detached inventory projection in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1`, enforcing Selection/OptionalOffers "Complete choices, declared reasons and exact pins" and RequiredInventories "Resolve each root with no optional selections at SourceCommit"; include declaring ID, key, target identity/folder, reason, sidecar/index and selected flag, exposing only active-component offers without activating them.
- [X] T014 [US1] Bind selected local catalog/artifact inputs in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` with Catalog "Existing generated JSON shape; one unambiguous selected record", CatalogUrl "Provenance only; never dereferenced by this increment", Archive "One candidate under explicitly supplied artifact directories" and Extensions "Per-extension payload, provenance, command and intended paths"; use `<id>-<version>.zip` only as a candidate hint, invoke bounded verification and reject ambiguity/mismatch without fallback, downloads, rebuilding or opening declined ZIPs.
- [X] T015 [US1] Assemble approval-relevant snapshots and exact intended paths in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` with ConsumerSnapshot "Approval-relevant state, including absence and unresolved operations"; record workspace device/inode, runtime/tool identities and every inspected path's presence/type/identity/mode/hash, preserving existing unrelated entries and accounting for operation parent/temporary paths and runtime chmod traversal.
- [X] T016 [US1] Implement the fingerprint projection in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` with Fingerprint "SHA-256 or null" and "Lowercase digest of the canonical approval projection; null if blocked"; use "UTF-8 compact JSON, object keys sorted ordinally and arrays ordered by their defined keys" according to the data model's Fingerprint Ordering section, including UTF-8 byte comparison, numeric indexes, all collection keys, recursive byte tie-breakers, explicit execution positions and canonical JSON encoding; bind all selected source/tool/catalog/artifact/runtime/workspace/state/write evidence, exclude timestamps/presentation/ephemeral details and derive the exact operation directory without hashing its own derived name.
- [X] T017 [US1] Wire complete preview orchestration and script/object output in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1`, enforcing Ready "True only when every required input/precondition is available and valid"; aggregate independently discoverable blockers, emit Ready false/Fingerprint null on any blocker and keep manager construction, consumer extraction, locks, evidence, chmod and caches unreachable from preview; unsupported interim apply/selection paths must fail closed, not masquerade as ready implementation.
- [X] T018 [US1] Extend `.github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1` with determinism, empty/singleton arrays, native mode/notice verification, duplicate-key/member rejection, source cleanup and exact-tool identity cases; permute unordered catalog/artifact arguments, tools, reasons, snapshots and intended writes and require equal fingerprints, including equal-key tie-breakers and case/non-ASCII comparison cases; changing authored indexes, execution positions, bound values or raw catalog/artifact bytes must change or block approval, and ordinary Markdown links must never create dependencies.
- [X] T019 [US1] After explicit test approval, run the focused suite through the existing root npm/Pester runner and record actual executed counts, failures/skips, prerequisite identity and before/after preview preservation in `specs/004-bounded-workspace-installer/quickstart.md`; require nonzero tests and zero hidden prerequisite skips, leaving any unavailable check unverified rather than passing it.
- [X] T020 [US1] Document only the implemented read-only preview and its validated limits in `.github/skills/skill-library/SKILL.md`, including exact local inputs, blocked preview handling, trust/integrity limits and the distinction between preview readiness and apply/editor acceptance; keep unimplemented optional apply and broader installation claims explicitly out of current support.

**Checkpoint / MVP**: US1 alone provides the read-only preview. It does not install guidance, close
editor gates or authorize any later operation. A root preview is independently useful without US2-US4.

## Phase 4: User Story 2 - Install The Approved Root In One Workspace (P2)

**Goal**: Apply an unchanged approved root-only preview through the pinned upstream installer and
verify canonical payload, command and runtime registration without touching unrelated state.

**Independent test**: In a synthetic consumer, apply one ready root fingerprint; verify exact identity,
bytes/modes/notices, registration, command and receipt. Preserve source, profile and unrelated consumer
state; corrupt artifacts and stale/missing approval must never reach upstream installation.

### Tests For US2

- [X] T021 [US2] Author root apply contract tests first in `.github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1` for explicit matching approval, recomputation instead of caller-edited plans, same-open-stream verification, literal version equality, guarded ownership, correct registration/resource verification, minimum failure preservation and separate JSON/diagnostic streams; seed unresolved state both before preview and after a ready preview, asserting refusal before reservation/upstream calls and unchanged prior evidence; request approval before demonstrating expected failures.

### Implementation For US2

- [X] T022 [P] [US2] Implement only the approved archive apply route in `.github/skills/skill-library/scripts/Invoke-SpecKitInstall.py`: hash/inspect/rewind one regular unlinked open ZIP stream and pass that same stream to `ExtensionManager(workspace).install_from_archive` with `"1.2.3"`, `priority=10`, `force=False`, `archive_file=stream`, `expected_id` and `expected_version`; reject literal-version/digest drift and never substitute custom extraction, the compatibility alias, development links, network acquisition or CLI refresh/scaffolding.
- [X] T023 [US2] Implement post-install verification in `.github/skills/skill-library/scripts/Invoke-SpecKitInstall.py` for every canonical source byte/mode and notice, expected rendered Copilot command, literal extension identity/version, registry/config additions and unchanged unrelated inspected state; treat skipped registration, warnings, extra paths and incomplete evidence as failures even after an upstream success return.
- [X] T024 [P] [US2] Implement apply approval/revalidation in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` using original inputs only, recomputing the full ready preview and requiring exact lowercase ReviewedFingerprint equality; invoke T007's unresolved-operation guard before reservation, rejecting missing/stale approval, incomplete prior state, changed selection/tool/state and caller-supplied result objects before reservation or any runtime call; US2 apply must not depend on later T034 hardening for this refusal.
- [X] T025 [US2] Wire exclusive namespace/lock reservation and Prepared receipt creation in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1`, then recheck approval state accounting only for declared owned lock/namespace/marker creation; flush approved inputs before delegation, reject unknown ownership and accurately report any evidence created before a post-reservation refusal.
- [X] T026 [US2] Launch the bridge as a fresh `-I -B` interpreter from `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1`, setting child-only TMPDIR to the private approved operation scratch before imports; preserve host environment/profile/package settings, capture sanitized upstream diagnostics separately and prohibit project-code or current-directory import fallback.
- [X] T027 [US2] Wire the root through ordered apply primitives in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1`, flushing Attempting before the upstream call and Verified only after all postchecks; enforce every model state transition, stop on the first failure/cancel or receipt failure, retain ambiguous files and prior verified state, and never roll back/delete or claim absent writes without evidence.
- [X] T028 [US2] Complete the root apply result/exit surface in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` with per-extension completed/failed/unknown/pending subsets, observed paths and recovery locations; emit Completed only after all selected entries and final evidence are verified/flushed, release only a provably owned safe lock and retain ambiguous lock/evidence for inspection.
- [X] T029 [US2] After separate test approval, run root apply/refusal/verification cases through the focused configured runner and record exact results in `specs/004-bounded-workspace-installer/quickstart.md`, proving occupied same-version targets, byte corruption and stale approval preserve caller content; do not infer real runtime/editor acceptance from mocks.
- [X] T030 [US2] Add the implemented approved root-install workflow and evidence locations to `.github/skills/skill-library/SKILL.md`, retaining first-install-only/no-profile/no-upgrade/no-network constraints, minimum stop/preserve behavior, manual inspection requirements and separate test/build/consumer/editor approvals.

**Checkpoint**: Root apply is independently testable with a synthetic installer. Real consumer
acceptance remains pending US4's failure hardening and the final separately approved runtime gates.

## Phase 5: User Story 4 - Preserve Local Work And Diagnose Partial Installation (P2)

**Goal**: Make interruption, cancellation and uncertain outcomes precise and block ambiguous retries
without force, adoption, automatic cleanup or rollback.

**Independent test**: Fault/cancel before, during and after delegation/registration/receipt writes;
terminate a child after durable intent. Compare preserved caller content and verified/failed/unknown/
pending subsets, then prove a new apply refuses unresolved state. Use an internal synthetic two-entry
plan to exercise multi-step primitives without exposing a caller-edited plan or depending on US3.

### Tests For US4

- [X] T031 [US4] Author preservation/recovery tests first in `.github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1` for exact-version/local-edit/orphan/command conflicts, cancellation and child loss at each durable boundary, receipt-write failures and a verified first/failed second synthetic extension; assert existing bytes/modes, stopped invocation counts and retry refusal, obtaining approval before expected-failure execution.

### Implementation For US4

- [X] T032 [P] [US4] Harden stage-bounded exception/warning and incomplete-output reporting in `.github/skills/skill-library/scripts/Invoke-SpecKitInstall.py` using the established bridge contract; distinguish reported failure from uncertain copy/registration results, preserve all partial paths, suppress false success and never use a retry, cleanup or replacement installer to resolve ambiguity.
- [X] T033 [P] [US4] Harden observed-path/outcome classification in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` against the established bridge contract, recording partial payload/command/registry effects and evidence-write failures without relabelling a previously Verified extension or uncertain writes as absent; return the last durable step/location if final evidence cannot be persisted.
- [X] T034 [US4] Harden the existing T007/T024 unresolved-operation gates in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` against the expanded fault/termination matrix: torn/missing/inconsistent receipts, abandoned locks and Prepared/Running/Attempting intent remain unresolved/Unknown and block further apply; require a valid owner marker, preserve completed receipts as evidence only, and never delete locks automatically or treat equal bytes as ownership; do not defer the minimum retry guard to this phase.
- [X] T035 [US4] Harden sequential state revalidation and cancellation in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` so each next target matches approved preconditions plus earlier verified writes, the first failure/cancel stops all remaining entries and retained state requires deliberate maintainer reconciliation/new preview; completed targets continue to block reapplication.
- [X] T036 [US4] Complete the fault/termination matrix in `.github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1`, asserting armed spies, durable intent-before-call ordering, lost-process classification, before/after mode/profile/source preservation and zero automatic resume/repair/uninstall/recursive cleanup; isolate process termination inside synthetic disposable fixtures.
- [X] T037 [US4] After explicit test approval, run the focused fault/conflict/cancellation suite and record executed case counts and per-boundary observations in `specs/004-bounded-workspace-installer/quickstart.md`; keep any unavailable real filesystem/process effect unverified and block runtime-readiness claims on a missing failure gate.
- [X] T038 [US4] Document observed partial-state reporting and deliberate reconciliation in `.github/skills/skill-library/SKILL.md`, requiring evidence preservation outside the active operation namespace, separately approved manual/runtime actions and fresh clean-target preview; do not add a reconcile/delete/force/resume command or promise atomicity/power-loss durability.

**Checkpoint**: Failure behavior is independently testable using synthetic ordered entries. Apply can
now proceed to optional-selection integration without deferring any ownership/retry safeguard.

## Phase 6: User Story 3 - Choose Optional Extensions Separately (P3)

**Goal**: Accept explicit reachable optional choices as separate required-only extensions, preserving
the root artifact, independent ownership and unselected nested/declined choices.

**Independent test**: Offer two peers, select one and leave one unavailable/declined. Verify two
separate extensions, unchanged root ZIP, complete overlapping resources, a changed approval fingerprint,
zero declined-artifact opens/downloads and no auto-selection of newly exposed optional offers.

### Tests For US3

- [x] T039 [US3] Author optional-selection contract/integration tests first in `.github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1` for one-of-two selection, nested offers defaulting off, active-key/reason attribution, shared required resources, stale selection approval and separate per-root artifacts; obtain approval before expected-failure execution and assert declined ZIP/network spies remain untouched.

### Implementation For US3

- [x] T040 [US3] Extend the detached selection projection in `.github/skills/skill-library/scripts/Invoke-InventoryPreview.ps1` to expose selected optional targets from the existing combined validator, enforcing ExtensionRoots "Root first, distinct selected optional targets sorted by ID; at most 16"; retain every declared inclusion reason, expose new offers only from active components and return no temporary-backed data or second dependency resolver.
- [x] T041 [US3] Wire explicit optional inputs in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1` with OptionalSelection "Sorted unique selection keys" and "Existing `id/selectionKey` semantics; no inferred selections"; reject duplicate supplied/unknown/inactive keys through the authoritative validator, keep all undeclared choices off and require a complete revised preview rather than unreviewed incremental apply.
- [x] T042 [US3] Compose each selected root's no-option required-only inventory and artifact binding at the same frozen commit in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1`, enforcing Overlaps "Source path/hash and owning extension IDs; no physical deduplication"; preserve each extension's complete resources/notices under its own tree, retain root ZIP identity and never open/materialize a declined optional artifact.
- [x] T043 [US3] Connect the ordered selected-extension list to the existing guarded apply loop in `.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1`, binding all optional reasons/pins/artifacts/paths into the fingerprint and revalidating expected state between installs; preserve earlier Verified entries and stop/report failed/unknown/pending subsets when a later optional install fails.
- [x] T044 [P] [US3] Add final optional/overlap regression cases in `.github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1` after T043 for duplicate target offers, required/optional overlap, 16-root limit, missing selected artifacts, unchanged root digest and failure on a selected peer; ensure nested and declined choices remain inactive without hidden fetch/build fallback.
- [x] T045 [US3] After separate test approval, run optional-selection and multi-extension failure cases through the focused configured runner and record concrete outputs/counts in `specs/004-bounded-workspace-installer/quickstart.md`; demonstrate the SC-003 case with two offers and one accepted, not an all-options-selected substitute.
- [x] T046 [P] [US3] Draft the bounded optional-selection workflow in `.github/skills/skill-library/SKILL.md` after T043, explaining separate required-only artifacts, revised approval, overlap ownership and newly exposed offers remaining off; keep execution/acceptance marked pending until T045 and later runtime evidence rather than claiming broad installer/publication support.

**Checkpoint**: All four stories are independently exercised through their scoped synthetic scenarios.
Full feature acceptance still requires the approved runtime/editor and regression gates below.

## Phase 7: Polish And Cross-Cutting Validation

**Purpose**: Integrate the suite, synchronize proven guidance and close execution gates only with
their required approvals and observed evidence.

- [x] T047 [P] Add the new focused suite to the adjacent suite list in `.github/skills/skill-library/scripts/Invoke-Tests.ps1`, preserving pinned Pester 5.7.1, the existing interpreter environment convention, nonzero-test enforcement and no-provisioning behavior; keep the root npm runner's existing suite discovery rather than introducing another runner/framework.
- [x] T048 [P] Consolidate implemented limits, observed evidence and durable drift lessons in `.github/skills/skill-library/SKILL.md`, including current upstream API/module hashes, Copilot rendering/registration paths, temporary/mode effects and operation-state recovery; remove superseded general-installation statements only where bounded support is actually verified, preserving native use and separate publication/rights/signing/platform scope.
- [x] T049 Reconcile commands, prerequisites, proposed-versus-observed results and exact approval gates in `specs/004-bounded-workspace-installer/quickstart.md` against the implemented interface; retain non-atomic/stable-workspace limitations, keep machine/private identifiers out of tracked evidence and do not close editor acceptance from static registration or manual file reads.
- [x] T050 After explicit regression-test approval, run the new focused suite and existing adjacent metadata/preparation/inventory/archive/extension suites through the configured npm/Pester paths and record actual nonzero counts, failures/skips and interpreter identity in `specs/004-bounded-workspace-installer/quickstart.md`; this validates the shared inventory boundary without expanding to unrelated repository tests.
- [x] T051 After separate real-build and disposable-consumer preparation approval, use the existing archive/extension workflows to prepare trusted local root/selected-peer artifacts and a compatible initialized consumer for the guide in `specs/004-bounded-workspace-installer/quickstart.md`; record exact commit/digests and approved local inputs without downloads, hosting, publication or another checkout, and leave the task blocked if approval is absent.
- [x] T052 After explicit consumer-mutation approval, execute the ready preview/apply and approved interruption scenarios from `specs/004-bounded-workspace-installer/quickstart.md` using the real pinned runtime, observing actual scratch/bytecode/mode/write paths, installed resources/notices, registration and untouched source/profile/unrelated files; record SC-001 through SC-005 results and any retained partial state without substituting environment assertions or mocks for runtime evidence.
- [ ] T053 After separate editor-demonstration approval, record the SC-006 gate in `specs/004-bounded-workspace-installer/quickstart.md` using the discovered native load command and actual installed-only instruction/reference reads, distinguishing automatic loader attachment, owner observation and captured trace; preserve unverified status if discovery/invocation/read evidence is unavailable and forbid source/profile/declined-skill fallback.
- [x] T054 Run repository-configured scoped pre-commit/static/link checks for the touched source and design files, inspect saved output and Git diff for unrelated edits, and reconcile actual completion/evidence in `specs/004-bounded-workspace-installer/tasks.md`; mark tasks complete only when their action and required approval/observable gate occurred, leaving unavailable runtime/editor tasks explicitly pending and making no implicit commit/push/release.

## Dependencies And Execution Order

### Phase Dependencies

```text
Setup T001-T003
  -> Foundation T004-T009
  -> US1 T010-T020 (read-only MVP)
  -> US2 T021-T030 (guarded root apply)
  -> US4 T031-T038 (failure/retry hardening)
  -> US3 T039-T046 (optional multi-extension integration)
  -> Polish T047-T054 (approved regression/runtime/editor evidence)
```

The sequence is an implementation dependency graph, not a command to execute the phases now. US1
needs no other story. US2 reuses US1 preview/fingerprint; US4 reuses US2's guarded loop and can test two
internal synthetic entries without US3. US3 requires US1's preview, US2's verified apply and US4's
failure/ambiguity handling. Each story can be verified without requiring a later story.

The independently useful US1 checkpoint includes its blockers and preservation checks. Apply is not
ready for a real consumer until the US4 safeguards and final approved real-runtime checks are complete.
The optional acceptance case uses a fresh approved consumer, not adoption of an already installed root.

### Within Each Phase

1. Complete prerequisites and inspect current files/owning guidance before editing.
2. Author story contract tests, then obtain approval to observe the expected failing assertion.
3. Implement models/helpers, behavior and orchestration in that order; serialize same-file changes.
4. Obtain approval for focused executable checks; record actual results and preserve failures.
5. Stop at the checkpoint if approvals or acceptance evidence are unavailable; never mark it passed.

US1 parallel implementation starts after T010; T014 waits for T011-T013. US2's T025 waits for the
approval guard T024; T026-T028 additionally require bridge installation/verification T022-T023. US4's
T034-T036 wait for T032-T033. US3's final test/document pair starts only after T043; T045 waits for T044.
Final acceptance tasks T050-T053 each retain their own execution prerequisites, not merely file order.

### Safe Parallel Examples

These are authoring examples, not delegation or test-execution authorization. No two listed tasks in
a pair edit the same file, and all their shared contract/prior-phase prerequisites must already exist.

| Scope | Ready Prerequisite | Different-File Tasks |
| --- | --- | --- |
| Setup | Saved contract | T001 tests harness; T002 PowerShell boundary; T003 Python transport |
| Foundation | Setup complete | T004 inventory projection; T005 PowerShell model; T006 Python probe |
| US1 | Foundation and T010 complete | T011 Python archive verifier; T013 PowerShell root/offer composition |
| US2 | US1 and T021 complete | T022 Python upstream apply; T024 PowerShell approval guard |
| US4 | US2 and T031 complete | T032 Python error evidence; T033 PowerShell outcome classification |
| US3 | US4 and T039-T043 complete | T044 test regressions; T046 pending-acceptance guidance draft |
| Polish | All story implementations complete | T047 adjacent runner list; T048 owning skill guidance |

Do not parallelize full stories: their shared files and behavioral dependencies make that unsafe here.
Tests within the single focused test file are authored serially except alongside a different-file
implementation/document task shown above. Real-runtime and editor demonstrations are sequential.

## Coverage And Acceptance

| Requirements | Task Coverage | Observable Gate |
| --- | --- | --- |
| FR-001, FR-009, FR-010 | T002, T006-T008, T012, T015, T023-T028, T031-T038 | One approved workspace; unchanged unrelated/profile/source bytes and modes |
| FR-002, FR-003, FR-005 | T004, T013-T014, T018, T039-T046 | Existing validator; separate required-only roots; declined artifacts untouched |
| FR-004, FR-006 | T005, T010-T019, T021, T024-T025 | Complete read-only preview; canonical fingerprint; stale approval refused |
| FR-007, FR-008 | T006, T011-T012, T021-T023, T051-T052 | Same verified stream; existing runtime registration; exact resources/notices |
| FR-011, FR-012, FR-013 | T008-T009, T027-T028, T031-T038, T043 | Durable intent and accurate subsets; preserve/stop/block ambiguous retry |
| FR-014, FR-016 | T002-T007, T014, T022, T026, T048-T054 | Fail without setup/network/profile/upgrade/cleanup/publication expansion |
| FR-015 | T023, T049, T052-T053 | Distinct installed bytes, registration, discovery, invocation and actual reads |
| SC-001, SC-002 | T019, T029, T045, T050-T052 | Exact selected identities; zero unpreviewed or unrelated writes |
| SC-003 | T039-T046, T051-T052 | One of two offers selected; separate peer; unchanged root; no declined access |
| SC-004 | T010, T018-T019, T021, T029, T031-T037, T050-T052 | Occupied/local-edit/stale/corrupt cases preserve content and refuse |
| SC-005 | T031-T038, T043-T045, T050-T052 | Every tested failure distinguishes subsets and blocks unsafe retry |
| SC-006 | T051-T053 | Approved disposable pinned runtime plus separately observed editor evidence |

## Implementation Strategy

### MVP First

Complete T001-T020 only: shared foundation and independently validated consumer-read-only root preview.
Review its exact artifacts, optional offers, paths and blockers. Do not equate this MVP with install,
editor loading, publication or consent to continue execution.

### Incremental Delivery

Add guarded root apply, then failure/retry hardening, then explicit optional multi-extension support.
Keep the root artifact unchanged, generated receipts separate from runtime authority and acceptance
claims no broader than actual evidence. Run real-runtime/editor demonstrations only after their
separate approvals; retain pending tasks when a gate cannot be performed.

### Completion Discipline

Generating this list marks no task complete. Follow shared approval/commit/privacy rules, record
durable lessons in their existing owner when implementation supplies evidence and preserve unrelated
work. Do not silently rewrite the specification, plan or recently edited research while implementing
these tasks; resolve an actual contract conflict explicitly rather than expanding the feature.
