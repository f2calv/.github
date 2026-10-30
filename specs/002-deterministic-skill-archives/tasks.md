# Tasks: Deterministic Skill Archives

**Input**: [Specification](./spec.md), [plan](./plan.md), [research](./research.md),
[data model](./data-model.md), [archive contract](./contracts/archive-build.md) and
[validation guide](./quickstart.md).

**Status**: All 43 implementation/convergence tasks and approved validation completed. The final
four-suite regression passed 245 tests; scoped lint and the earlier approved retained real pilot/rebuild passed.
No commits, pushes, branch changes, component version edits, installation or publication performed.

**Tests**: The specification's independent tests and measurable outcomes require synthetic coverage.
Write tests before their corresponding implementation. Request explicit approval before running
tests or archive scenarios, including an expected failing baseline. If approval or prerequisites
are unavailable, record the blocker and leave the execution gate unchecked; never install tools
or convert an unexecuted check into a pass.

**Organization**: Setup and foundations block all stories. Story phases follow priority order
because they extend the same command/writer. Each has independently observable acceptance criteria,
but no partial milestone establishes the complete `skill-archive/1` contract.

## Format And Paths

- Every task uses a checkbox, sequential ID and exact repository-relative file paths.
- `[US1]`, `[US2]` and `[US3]` identify story tasks only.
- `[P]` marks different-file work that may overlap at the dependency boundary specified below;
  it does not authorize delegation or concurrent edits to the same file.
- Keep runtime work within the existing skill-library bundle. No new project, metadata schema,
  archive framework, package installation, component version edit or dependency-pin edit is needed.
- Read applicable PowerShell, Python, test and customization-authoring instructions when implementing
  their files. Reuse existing helpers and fixtures rather than copying another resolver.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the existing runtime/test boundary without provisioning or running tests.

- [X] T001 Confirm the existing PowerShell 7.4+, CPython 3.11+, Git, PyYAML 6.0.3 and Pester 5.7.1 prerequisites, record selected existing interpreter and missing prerequisites in specs/002-deterministic-skill-archives/quickstart.md, and preserve the separate test-approval requirement; do not install or claim unobserved support.
- [X] T002 Create inert, dot-source/import-safe entry-point structure in .github/skills/skill-library/scripts/Invoke-Archive.ps1 and .github/skills/skill-library/scripts/Write-Archive.py, exposing Invoke-SkillArchive and an internal isolated writer boundary without writing output during load or implementing a second metadata resolver.
- [X] T003 Establish the adjacent synthetic archive suite in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 using existing minimal repository fixtures and complete captured helper bundles; keep all fixture Git mutations outside the source checkout and add no separate test framework or fixture-only production CLI options.

**Checkpoint**: Runtime locations and test-authoring surface are known. Syntax checks passed;
the approved phase-boundary setup smoke check passed 3 tests, with 0 failures/skips. No archives built.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Supply trusted source reads and baseline output safety before any usable archive path.

- [X] T004 Implement trusted bundle capture in .github/skills/skill-library/scripts/Invoke-Archive.ps1: capture entry point/writer, inventory/validation scripts, Git helper, metadata reader, both schemas and requirements; hash and execute the same captured bytes with explicit original repository/interpreter arguments. Apply “A missing, changed-during-capture or unreadable required bundle file fails.” Record “Versioned byte contract identifier `skill-archive/1`.”, “Existing trust label `invoked-tool-bundle`.”, logical file paths/digests and exact runtime identities without installation paths.
- [X] T005 Implement request validation and one-time commit resolution in .github/skills/skill-library/scripts/Invoke-Archive.ps1 using the existing Git helper. Apply RepoRoot's “Existing local repository; default is the invoked tool's repository, not caller location.”, SourceRevision's “Local revision, default `HEAD`; resolve once to a full commit and use only that commit afterward.” and SkillName's “Exactly one explicit nonempty native folder name; zero, duplicates or multiple values fail.” Reject unknown/optional-selection parameters even when empty, missing required values noninteractively, and preserve default PythonPath `python3` without installing prerequisites.
- [X] T006 Implement owned private scratch and staged-input handoff in .github/skills/skill-library/scripts/Invoke-Archive.ps1, outside the source repository and resolved Git administrative/common directories even when temporary environment settings point inside them; invoke trusted Python with `-I -B`, preserve byte-safe isolated Git reads, and fail rather than follow unsafe scratch links or execute historical payload code.
- [X] T007 Implement Linux/CPython prerequisite checks and output reservation in .github/skills/skill-library/scripts/Write-Archive.py. Apply OutputDirectory's “Absolute new directory with an existing trusted parent; no links, existing entries or source/Git containment.” and PythonPath's “Existing CPython interpreter with supported Linux filesystem APIs and installed PyYAML 6.0.3.” Reject unsupported platforms before reservation, missing/linked ancestry and ambiguous path components; use descriptor-relative no-follow traversal, component-aware containment, exclusive private `mkdir` and exclusive incomplete-marker/file creation without rename-overwrite or parent creation.
- [X] T008 Implement baseline output lifecycle and guarded rollback in .github/skills/skill-library/scripts/Write-Archive.py. Apply “The private ledger records directory/file device, inode, type, link count and expected content state.” Track successful creation immediately; close/sync files and directories, delete only unchanged provably owned entries, preserve replacements/foreign additions/changed content, refuse leftovers on retry and never recursively delete output. Provide the internal cleanup acknowledgment needed before successful completion.
- [X] T009 Implement CLI/object failure and result boundaries in .github/skills/skill-library/scripts/Invoke-Archive.ps1: inert dot-sourcing, terminating categorized object errors, one CLI JSON success/zero exit or sanitized stderr/nonzero failure. Apply “No success object is returned before cleanup and finalization complete.” Buffer SourceCommit, RootId, RootVersion, OutputDirectory, ArchivePath, ChecksumPath, ArchiveSha256, PayloadCount and ArchiveContract; never leak raw interpreter stderr, source content or configuration, and never emit a digest/success object on failure.

**Checkpoint**: Foundation is ready only when an eventual build can reserve safely, clean owned
state conservatively and suppress success on errors. No provisional unsafe writer is exposed.

## Phase 3: User Story 1 - Package One Skill Without Optional Bundles (Priority: P1)

**Goal**: Build one root's eligible committed required-only payload, with basic evidence and the
safe output boundary already in place. Optional preview behavior remains unchanged.

**Independent Test**: In a synthetic repository, package a root with required chains/diamonds,
shared external files/notices and an optional target having its own dependency. Every required
inventory file appears exactly once; optional-only files are absent, while independently required
overlap remains. Missing/multiple/repeated roots and optional selections fail without output.

### Tests For User Story 1

- [X] T010 [US1] Author CLI/object contract tests in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 for inert loading, defaults independent of caller location, exactly one root, zero/repeated/multiple roots, unknown and empty optional-selection parameters, noninteractive errors, supported prerequisite checks and one-success/no-partial-JSON behavior; execute an expected failing baseline only after explicit approval.
- [X] T011 [US1] Author required-only payload tests in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 for chains/diamonds, required/optional overlap, optional-only transitive exclusion, shared inherited/component/external notices, external instruction attribution, invalid unselected catalog records and ignored mandatory files; assert unchanged optional-closure inventory behavior and committed binary/empty/executable/Unicode/CRLF payloads rather than generated expected membership alone.

### Implementation For User Story 1

- [X] T012 [P] [US1] Adapt Invoke-SkillInventoryPreview in .github/skills/skill-library/scripts/Invoke-Archive.ps1 without changing its public API: exactly one root and empty optional selections, whole-catalog validation and existing committed eligibility. Apply “`OptionalSelections` must be empty”, “`Roots` must match the one requested native folder” and “active component reasons may be `root` or `required` only.” Preserve unique Files paths and every owner, reaching root, active required edge and effective declaration; do not filter a combined optional preview after resolution.
- [X] T013 [P] [US1] Build the generated manifest model in .github/skills/skill-library/scripts/Write-Archive.py with SchemaVersion “Generated evidence version `1`; never added to authored sidecars.”, Root “Object containing selected component `Id`, `Version` and native `Folder`.” and OptionalSelections “Always an empty array, making the required-only boundary machine-visible.” Include SourceCommit, captured Builder, Components, Payload, GeneratedMembers and Limitations only; GeneratedMembers is “Exactly the `manifest.json` record: `Path`, `Role=build-evidence`, `Mode=100644`.” Payload records contain SourcePath, MemberPath, Mode, Size, Sha256, Owners and Reasons; apply “`MemberPath` is exactly `payload/` plus `SourcePath`”, “`Mode` is `100644` or `100755`; `Size` is an integer byte count.” and “Owner and reason collections remain arrays even when empty or singleton; reasons retain declaration indexes and loading purpose.”
- [X] T014 [US1] Read each inventory file at its frozen full SourceCommit in .github/skills/skill-library/scripts/Invoke-Archive.ps1 through existing NUL-delimited tree/blob helpers; verify path/mode, stage exact bytes plus size/SHA-256 and fail on unavailable objects or mismatches without lazy fetch, checkout, filters or historical script execution. Preserve source files, index, HEAD, refs and local Git configuration.
- [X] T015 [US1] Implement exact-member ZIP construction in .github/skills/skill-library/scripts/Write-Archive.py: only manifest.json and one `payload/<SourcePath>` member per inventory file, no directory entries or scaffolding, stored entries and committed modes. Reuse eligibility/collision rules, reject unsafe/conflicting names, preserve native relative geometry without rewriting content, and recheck staged sizes/digests while reading through a new seekable output file. Close/sync the ZIP, hash its completed bytes and exclusively write/sync package.zip.sha256 with the lowercase hash, two ASCII spaces, `package.zip` and one LF; use the foundational guarded-finalization path before acknowledging completion.
- [X] T016 [US1] Integrate the captured inventory, staging, writer and completed ZIP/checksum pair in .github/skills/skill-library/scripts/Invoke-Archive.ps1; pass explicit repository/Git boundaries, remove inspection scratch before staging handoff and all remaining owned scratch before completion, require writer finalization acknowledgment, and return the sole buffered success result only after both outputs and cleanup succeed.
- [X] T017 [US1] Add the archive suite to .github/skills/skill-library/scripts/Invoke-Tests.ps1 alongside metadata, preparation and inventory, preserving pinned Pester 5.7.1, installed-interpreter selection, nonzero-per-suite counts and no setup/network side effects; do not run the runner as part of this edit without approval.
- [X] T018 [US1] Request approval for the focused synthetic required-only/CLI gate using .github/skills/skill-library/scripts/Invoke-Tests.ps1 and record actual counts, membership/optional-exclusion results, source-state preservation and blockers in specs/002-deterministic-skill-archives/quickstart.md; leave this task pending when execution is not approved or any required check fails.

**Checkpoint**: Required-only packaging is demonstrable after the approved gate. This is the MVP
milestone, not permission to claim final byte-contract conformance or distribute/install artifacts.

## Phase 4: User Story 2 - Rebuild Identical Archive Bytes (Priority: P2)

**Goal**: Bind the exact builder tuple, normalize all ZIP/evidence bytes and prove independent
rebuilds rather than merely equivalent extracted payloads.

**Independent Test**: Build the same commit/root/tool/runtime tuple in separate temporary contexts
with different output paths, times, locale and umask; compare full bytes and SHA-256. Dirty/staged/
deleted-local/untracked state must not affect pinned source; changed eligible content must change
member bytes and archive digest. Different trusted tooling/runtime tuples are distinct inputs.

### Tests For User Story 2

- [X] T019 [US2] Author independent raw-header/manifest tests in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 for member order, local/central headers, timestamps, modes, ASCII/UTF-8 flags, CRC/sizes, empty extras/comments, no descriptors/ZIP64/encryption, canonical JSON and archive-size boundaries; use an independent inspector, not the writer's serializer as the only oracle, and obtain approval before running an expected failing baseline.
- [X] T020 [US2] Author repeat-build and input-identity tests in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 using independently created temporary contexts, changed clock/locale/umask/output names, dirty/staged/deleted-local/untracked source, older commits, missing objects and changed eligible blobs; assert captured trusted bytes/runtime identities rather than historical tooling execution, path leakage or unconditional cross-runtime equivalence.

### Implementation For User Story 2

- [X] T021 [P] [US2] Normalize every ZIP field in .github/skills/skill-library/scripts/Write-Archive.py per specs/002-deterministic-skill-archives/contracts/archive-build.md: manifest first, unsigned UTF-8 payload order, stored method 0, DOS epoch/date `0x0021`/time 0, creator system 3, create/extract version 20, ASCII flags 0/non-ASCII `0x0800`, full source modes shifted 16 bits and generated mode 100644, zero internal/DOS/reserved fields, empty extras/comments and no descriptors/ZIP64/encryption; use explicit ZipInfo rather than filesystem metadata or private encoding overrides.
- [X] T022 [P] [US2] Normalize provenance handoff in .github/skills/skill-library/scripts/Invoke-Archive.ps1: Builder.Files uses “Strict UTF-8-path-sorted logical paths and SHA-256 values of captured trusted tool inputs.” and Builder.Runtimes uses “Exact PowerShell, Git, CPython implementation/version and PyYAML versions.” Keep them distinct from SourceCommit, preserve source-derived attribution array order, and exclude absolute source/install/output/scratch paths, host identity, timestamps and random values from artifact evidence.
- [X] T023 [US2] Implement canonical JSON, fixed Limitations and conservative limits in .github/skills/skill-library/scripts/Write-Archive.py: sorted string keys, compact separators, unescaped strict UTF-8/no BOM/one LF, integer numbers only, rejection of floats/nonfinite/invalid Unicode/non-string keys, stable arrays and exact limitation strings/order from the archive contract. Apply “The manifest does not contain its own size/hash or the archive hash.” Reject more than 65,534 members including the manifest, names exceeding 65,489 UTF-8 bytes, or predicted complete archive size exceeding 1 GiB; calculate `22 + sum(76 + 2 * UTF8NameLength + ContentSize)` including canonical manifest bytes before persistent reservation and check final size.
- [X] T024 [US2] Complete deterministic source/manifest handoff in .github/skills/skill-library/scripts/Invoke-Archive.ps1 after T021-T023, preserving empty/singleton arrays, exact component versions, component inventory order and all reason indexes; ensure identical complete inputs yield identical evidence regardless of temporary/output context while changed source or captured builder inputs are represented as distinct evidence.
- [X] T025 [US2] Request approval for independent repeat-build/header/limit checks using .github/skills/skill-library/scripts/Invoke-Tests.ps1 and record complete-byte comparisons, independent hashes and exact observed runtime tuples in specs/002-deterministic-skill-archives/quickstart.md; disclose untested tuples and native Windows instead of inferring support from version minima or the earlier feature's waiver.

**Checkpoint**: Approved evidence establishes reproducibility for the recorded tuple only. No
cross-platform/runtime equivalence or publisher authenticity is inferred.

## Phase 5: User Story 3 - Inspect Build Evidence And Fail Safely (Priority: P3)

**Goal**: Independently verify attribution/integrity and exercise every output/cleanup boundary,
preserving caller-owned and ambiguous concurrent data without partial success.

**Independent Test**: Compare every manifest record/member/digest to a known synthetic inventory,
then run invalid source/member/destination, competing reservation and injected failure scenarios.
Assert nonzero categorized failure, no success JSON/digest, unchanged caller state, deletion only
of unchanged owned files, and explicit retained-path recovery diagnostics.

### Tests For User Story 3

- [X] T026 [US3] Author independent evidence/checksum tests in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 comparing every member's source path, full commit, mode, size, SHA-256, owners/reasons, exact component versions and effective license/notice sources against the fixture/inventory; verify generated-member attribution, no circular self-hash, fixed limitations and tamper detection without implying signatures or redistribution approval; obtain approval before execution.
- [X] T027 [US3] Author refusal/caller-state tests in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 for invalid catalog/local objects, unsafe/conflicting paths, unsupported modes/platforms, existing empty/nonempty directories/files/dangling links, linked ancestors, missing parents, source/Git containment and prefix-lookalike directories; include scratch environment paths inside managed content and verify files/index/HEAD/refs/local configuration remain unchanged on success and failure. Add explicit fail-closed subprocess/network tripwires for download, provisioning, install, version-preparation and publication attempts, plus inert historical payload sentinels, without performing the forbidden operations; verify the tripwires themselves detect synthetic attempts.
- [X] T028 [US3] Author internal fault-injection tests in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 for create/write/close/sync/hash, staged-content change, scratch cleanup, marker removal and final acknowledgment failures; inject through internal function/process seams rather than public production flags, and assert category, sanitized diagnostics, retained recovery paths and zero partial success/digest.
- [X] T029 [US3] Author competing reservation/interference/interruption tests in .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1: exactly one destination winner, no overwrite of the loser, foreign additions/replacements/changed content preserved, cleanup failure suppressing success, process-death remnants refused including unmarked/finalized-but-unacknowledged directories; use controlled synchronization, not timing-only sleeps or hostile-writer protection claims.

### Implementation For User Story 3

- [X] T030 [P] [US3] Complete independent output verification in .github/skills/skill-library/scripts/Write-Archive.py: close/sync ZIP before hashing all bytes, write “the lowercase SHA-256 of the completed ZIP, two ASCII spaces, `package.zip` and one LF.” to the detached file, validate pair contents/digests, exact entries and ownership identities, and exclude absolute paths from artifact/checksum. Require exactly package.zip and package.zip.sha256 after finalization, with no incomplete marker.
- [X] T031 [P] [US3] Complete failure-category mapping in .github/skills/skill-library/scripts/Invoke-Archive.ps1 for Prerequisite, Selection, Source, Validation, Eligibility, Inspection, Archive, Output and Cleanup; preserve cleanup failure precedence/recovery locations, sanitize unknown failures and interpreter stderr, and verify dot-sourced errors do not exit the host or emit buffered success/digests during partial failure.
- [X] T032 [US3] Harden fault paths in .github/skills/skill-library/scripts/Write-Archive.py using the ownership ledger: revalidate device/inode/type/link count/content before finalization or unlink, retain ambiguous state, clean only proven unchanged owned entries and matching empty directories, remove marker only after scratch cleanup acknowledgment, sync final directory/parent and close required handles; preserve trusted-parent/exclusive-use limits and make no atomic-pair/crash-rollback guarantee.
- [X] T033 [US3] Complete cleanup/finalization coordination in .github/skills/skill-library/scripts/Invoke-Archive.ps1 with the writer: require all captured-tool/staging cleanup acknowledgments, propagate retained owned/ambiguous recovery paths without raw content, suppress success on failed final sync/close/cleanup and reject retry adoption rather than silently deleting leftover output.
- [X] T034 [US3] Request approval for the evidence/refusal/race/fault-injection gate using .github/skills/skill-library/scripts/Invoke-Tests.ps1 and record observed categories, ownership preservation, cleanup outcomes, caller-state checks and exact counts in specs/002-deterministic-skill-archives/quickstart.md; leave unexecuted/failed scenarios open and do not claim native Windows safety.

**Checkpoint**: All three stories meet their approved independent criteria. Retained recovery
files are disclosed; their existence is not a successful artifact or automatic cleanup permission.

## Phase 6: Polish And Cross-Cutting Concerns

**Purpose**: Update the existing authority after implementation and record final observed gates.

- [X] T035 [P] Update .github/skills/skill-library/SKILL.md only after archive implementation: document actual CLI/object usage, required-only boundary, layout/digest verification, installed prerequisites, output/recovery threat model and observed platform limits; retain native use, optional inventory preview, rights/authenticity separation and unimplemented installation/publication. Update its description and maintaining section where supported behavior now differs; do not add another rule owner or change authored component versions.
- [X] T036 [P] Reconcile specs/002-deterministic-skill-archives/quickstart.md with the implemented interface and observed evidence, and scan README.md for affected archive claims/links, changing only stale statements; keep planned versus executed results distinct and make no loader/Windows/publication claims without evidence.
- [X] T037 Run editor diagnostics and the configured root pre-commit hooks through .github/skills/tooling-pre-commit/scripts/Invoke-PreCommit.ps1 for changed .github/skills/skill-library/scripts/Invoke-Archive.ps1, .github/skills/skill-library/scripts/Write-Archive.py, adjacent tests/runner and design/authority documents; record results in specs/002-deterministic-skill-archives/quickstart.md, review formatter edits and rerun the same selection when changed rather than bypassing hooks.
- [X] T038 Request explicit approval for the final affected metadata, preparation, inventory and archive regression gate through .github/skills/skill-library/scripts/Invoke-Tests.ps1 with the existing interpreter; record actual nonzero-per-suite counts, skips/failures and unchanged optional-preview behavior in specs/002-deterministic-skill-archives/quickstart.md, with no prerequisite installation or invented pass.
- [X] T039 Request explicit approval for the real required-only pilot/rebuild/digest inspection described in specs/002-deterministic-skill-archives/quickstart.md, using new caller-approved destinations outside source/Git directories and .github/skills/skill-library/scripts/Invoke-Archive.ps1; inspect optional-only exclusion and complete bytes, record actual source/root/builder tuple and outcomes, and leave all output uninstalled/unpublished without automatic deletion of caller artifacts.
- [X] T040 Recheck every FR/SC mapping below and the constitution against observed evidence in specs/002-deterministic-skill-archives/quickstart.md; close only completed tasks in specs/002-deterministic-skill-archives/tasks.md, preserve approval/support gaps as pending, report retained recovery material and customization feedback, and make no commits, pushes, version/tag/release edits or changes to the still-In-Progress distribution ADR without separate authorization.

## Dependencies And Execution Order

### Phase Dependencies

```text
Setup T001-T003
  -> Foundation T004-T009
  -> US1 T010-T018: required-only MVP
  -> US2 T019-T025: deterministic bytes
  -> US3 T026-T034: evidence and failure verification
  -> Close-out T035-T040
```

Story-level independence here means independently checkable outcomes, not independent code branches:
US2 depends on US1's working payload path; US3 depends on US2's finalized byte/evidence representation.
Output refusal and guarded cleanup start in the foundation, not after the first usable writer.

### Within Each Phase

1. Complete setup before foundation; foundation tasks are sequential because capture, paths,
   ownership and error boundaries depend on earlier work in the same files.
2. Author each story's tests first. An approved expected-failure run precedes corresponding behavior
   changes when available; without approval, do not run it or mark the gate complete.
3. After T011, T012 and T013 may overlap. T014 depends on T012, T015 on T013/T014, then T016-T018
   integrate and verify in order. Never edit the test suite or orchestrator concurrently with itself.
4. After T020, T021 and T022 may overlap. T023 follows T021 in the writer; T024 waits for T021-T023,
   and T025 is the story's approved execution/evidence gate.
5. After T029, T030 and T031 may overlap. T032 follows T030, T033 waits for T031/T032, then T034
   verifies the completed lifecycle. All fault-test edits T026-T029 remain sequential in one file.
6. T035 and T036 may overlap after T034. T037 precedes final approved regression/pilot checks
   T038/T039; T040 closes only observed gates. Any later behavior edit requires affected checks
   again under the existing approval scope.

### Approval Dependencies

T018, T025, T034, T038 and T039 are execution gates, not blanket permission supplied by this task
list. Test-authoring tasks likewise do not authorize running their expected-failure checks. A
declined or unavailable gate is a real blocker to a verified milestone, not an accepted skip.
No phase creates a branch/checkout, commits, pushes or publishes. Any later commit still requires
the owning privacy/branch rules and explicit authorization; do not infer it from phase completion.

## Parallel Examples

### User Story 1

After T011, T012 implements the PowerShell inventory adapter in
`.github/skills/skill-library/scripts/Invoke-Archive.ps1` while T013 implements the declared manifest
model in `.github/skills/skill-library/scripts/Write-Archive.py`. Both use the fixed contract;
join at T015-T016. Do not parallelize T010/T011: they edit the same test file.

### User Story 2

After T020, T021 normalizes Python ZIP fields while T022 normalizes PowerShell provenance handoff.
Their distinct files allow overlap against the existing contract. T023 edits the writer after T021;
T024 joins all resulting changes before the repeat-build gate.

### User Story 3

After T029, T030 verifies the Python output pair while T031 completes PowerShell failure mapping.
T032 then hardens the same Python lifecycle file; T033 integrates acknowledgments only when both
sides are ready. Keep T026-T029 sequential despite their different scenario groups.

## Requirements Traceability

| Requirement | Owning tasks |
| --- | --- |
| FR-001: one explicit root/local commit | T005, T010, T012 |
| FR-002: reuse validation and eligibility | T004, T011, T012 |
| FR-003: required payload/external files/notices once | T011-T015, T026 |
| FR-004: no optional selections/optional-only payload | T005, T010-T012, T018 |
| FR-005: committed bytes/modes, inert history, caller state | T006, T014, T020, T027, T033 |
| FR-006: native layout, explicit evidence, safe names | T007, T013, T015, T019, T027 |
| FR-007: identical normalized bytes for recorded inputs | T019-T025 |
| FR-008: derived source/builder/closure/rights attribution | T004, T013, T022-T024, T026 |
| FR-009: independent detached artifact digest/no self-hash | T016, T023, T026, T030 |
| FR-010: new safe output, conservative recovery, cleanup | T006-T009, T027-T034 |
| FR-011: sanitized failures/no partial success | T009, T010, T028, T031-T034 |
| FR-012: no network/setup/install/version/Git writes/publication | T001, T004-T006, T014, T017, T027, T038-T040 |
| FR-013: declarations separate from rights/authenticity | T013, T023, T026, T035-T036 |
| FR-014: optional inventory unchanged | T011, T012, T038 |
| FR-015: actual supported guidance/native use | T001, T025, T035-T039 |
| SC-001: exact required-only membership | T011, T018, T039 |
| SC-002: independent identical builds per supported tuple | T019-T025, T039 |
| SC-003: complete attributable/verifiable evidence | T013, T026, T030, T034 |
| SC-004: failures preserve caller-owned state | T027-T034 |
| SC-005: context independence/content-change sensitivity | T020, T025, T039 |
| SC-006: zero forbidden side effects/no unsupported claims | T027, T035-T040 |

## Implementation Strategy

### MVP First

1. Finish setup and output-safe foundations.
2. Implement US1 and obtain approval for its independent synthetic gate.
3. Stop at T018 for a required-only local packaging demonstration. This milestone is not the final
   deterministic-format guarantee, an installer or permission to publish.

### Incremental Completion

1. Complete US2 and its observed same-tuple byte/header gate before claiming reproducibility.
2. Complete US3 and fault/ownership evidence before declaring the full archive contract verified.
3. Update the existing owning guidance, run scoped static checks, and obtain approval for final
   regressions and the real pilot. Keep source/catalog versions and all Git publication state intact.
4. Record evidence at each boundary, leave blocked tasks unchecked and report limits explicitly.
   Do not expand this feature into optional downloads, extension loading, installation or publication.

## Task Totals

| Group | Tasks | Count |
| --- | --- | --- |
| Setup | T001-T003 | 3 |
| Foundation | T004-T009 | 6 |
| US1 | T010-T018 | 9 |
| US2 | T019-T025 | 7 |
| US3 | T026-T034 | 9 |
| Polish/close-out | T035-T040 | 6 |
| Convergence | T041-T043 | 3 |
| Total | T001-T043 | 43 |

Eight `[P]` tasks form four independent-file pairs at explicit boundaries; none permits concurrent
changes to the shared test suite or a partially implemented dependency. Counts describe the task
inventory; observed execution evidence is recorded in the validation guide.

## Phase 7: Convergence

- [X] T041 Disclose the exact retained inventory-inspection scratch location when its cleanup fails in
   .github/skills/skill-library/scripts/Invoke-Archive.ps1, preserving the existing inventory API and
   cleanup-failure precedence. Add a focused injected inventory-cleanup failure case in
   .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1 asserting a terminating Cleanup
   error, the retained recovery path, unchanged caller state, no completed output and no success digest.
   Request approval before execution and record observed results in
   specs/002-deterministic-skill-archives/quickstart.md per FR-010, US3/AC4 and T033 (partial).
- [X] T042 Complete the frozen-source checks in
   .github/skills/skill-library/scripts/tests/Invoke-Archive.Tests.ps1: advance fixture HEAD and build
   the older recorded commit, remove a required committed blob from a separate disposable fixture and
   assert categorized failure without fetching, output or caller-state changes, and verify that an
   eligible blob change alters the corresponding archive member bytes as well as its artifact digest.
   Keep mutations inside synthetic fixtures, request approval before execution and record actual
   results in specs/002-deterministic-skill-archives/quickstart.md per T020, T027 and SC-005 (partial).
- [X] T043 Reconcile the existing completion markers and status summary in
   specs/002-deterministic-skill-archives/tasks.md against inspected implementation and approved
   execution evidence in specs/002-deterministic-skill-archives/quickstart.md. Close only satisfied
   obligations, retain unresolved recovery/source-check work as pending, and refresh the final FR/SC
   audit after the approved T041-T042 checks; do not treat recorded aggregate test counts as proof of
   the missing scenarios per T040 (partial).
