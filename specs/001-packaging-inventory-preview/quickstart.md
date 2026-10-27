# Validation Guide: Packaging Inventory Preview

The committed preview, optional attribution and detailed declaration review are implemented and have
passed their synthetic checkpoints. The final cross-cutting gates are recorded below. Obtain separate scoped approval before
tests; this guide does not authorize provisioning, commits or publication.

## Prerequisites

- PowerShell 7.4+, local Git and Python 3.11+ with PyYAML 6.0.3 already installed.
- Pester 5.7.1 for approved synthetic tests; use the pinned module, not auto-loading.
- A local committed library with valid metadata/defaults and mandatory declared files.
- Implemented preview command, updated focused runner and adjacent inventory suite.

Run examples from the repository root in PowerShell; supply an existing interpreter. No package
installation or feed change is included. See the [contract](contracts/inventory-preview.md) and
[data model](data-model.md) for output definitions.

## Review a Committed Selection

```powershell
$python = '/path/to/python'
$script = './.github/skills/skill-library/scripts/Invoke-InventoryPreview.ps1'
$preview = & $script -SkillName patterns-ports-and-adapters -PythonPath $python |
    ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Preview failed.' }
$preview | ConvertTo-Json -Depth 64
```

Expected: full source commit, root's required closure, eligible committed internal files and
notices with all reasons. Unselected optionals add nothing. Output excludes working changes and
explicitly disclaims package/release/rights approval.

The synthetic required-closure case selects `example`, which requires `dependency`, which requires
`leaf`. Review these exact expectations:

- Components are `dependency`, `example`, `leaf` in ordinal order, each version `1.0.0` and each
    attributed to the fixture's committed OID; every `RootIds` array contains `example`.
- Files are the three committed `SKILL.md` files, the three `skill.metadata.yaml` files,
    `.github/skills/leaf/data.bin` and `LICENSE`: eight unique paths, ordinally ordered.
- The binary blob preserves bytes `00 FF 80` during inert inspection and reports Git mode
    `100755`; no payload bytes appear in JSON. Separate snapshot coverage checks `00 FF 0D 0A 80`.
- The leaf retains the `dependency` incoming edge with `Field=required[0]`; the selected root
    retains a root reason. Shared `LICENSE` appears once with every including component owner.
- Source tracked/untracked bytes, index bytes, refs, HEAD and repository configuration match
    before/after. Deleted or dirty local files and local-only metadata never supply snapshot input.

## Include the Explicit Optional Relationship

```powershell
$preview = & $script -SkillName patterns-ports-and-adapters `
    -OptionalSelection patterns-ports-and-adapters/module-composition -PythonPath $python |
    ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Preview failed.' }
```

Expected at a commit retaining current declarations: both architecture components and any required
prerequisites. Shared `LICENSE` appears once with each inheriting component reason. External
instructions retain declaration kind/loading purpose. No unrelated skill payload.

Synthetic optional coverage verifies `example/extra` adds exactly `optional` and its required
`leaf`; `optional/nested` adds `nested` only when both reachable choices are explicit. Reordering
those choices leaves complete JSON unchanged. A diamond through `left` and `right`, rooted at
`example` and `other`, retains both leaf incoming edges and both reaching root IDs. A file internal
to `leaf` and external to `right` appears once with both owners and both declaration reasons.

## Pin Source and Check Local Independence

```powershell
$source = git rev-parse --verify HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve local source.' }
$first = & $script -SourceRevision $source -SkillName patterns-ports-and-adapters `
    -PythonPath $python
if ($LASTEXITCODE -ne 0) { throw 'Preview failed.' }
$second = & $script -SourceRevision $source -SkillName patterns-ports-and-adapters `
    -PythonPath $python
if ($LASTEXITCODE -ne 0) { throw 'Preview failed.' }
if (($first -join "`n") -cne ($second -join "`n")) { throw 'Unstable preview.' }
```

Expected: identical complete output and unchanged source state. Dirty-file, moving-reference,
historical-schema and deleted-local-file variants belong in synthetic fixtures, not ad hoc
mutations of this repository. Historical scripts must never run.

## Review Declaration Attribution

Inspect each component's `License.Value`, `SourcePath`, `Field=license` and `Origin`. An explicit
`MIT` override must cite that component's sidecar, even when repository defaults also say `MIT`.
Inherited declarations cite `.config/skill-library.yaml`; additional component notices do not replace
inherited notices. `Notices` and file reasons retain zero-based declaration indexes.

The synthetic shared-notice case includes default `LICENSE` and
`.github/skills/example/SHARED`, component `NOTICE`, `instructions.md` and `external-notice.txt`.
Review one unique entry per path, every including component owner, simultaneous inherited/internal
reasons for `SHARED`, and both external loading purposes. Missing, duplicate or ignored mandatory
declarations must fail without partial JSON or source-state changes. These are declarations, not
legal clearance or proof of redistribution rights.

## Approved Focused Tests

After explicit approval, the focused runner includes all three adjacent suites:

```powershell
& ./.github/skills/skill-library/scripts/Invoke-Tests.ps1 -PythonPath $python
if ($LASTEXITCODE -ne 0) { throw 'Focused tests failed.' }
```

Require a nonzero inventory-test count and zero failures; zero-test success is not evidence.
Existing metadata/preparation suites must pass because their shared process/reader boundary
changes. The runner must not install prerequisites.

| Scenario Group | Required evidence |
| --- | --- |
| Closure | Chains, diamonds, multiple roots, nested selected optionals, all reasons and deduplication. |
| Invalid requests | Unknown/duplicate/unreachable optionals, unconverted roots, mismatched pins and cycle rules; no partial stdout. |
| Committed input | Dirty index/worktree, local-only sidecars, moving refs and alternate local commit; no input mixing. |
| File identity | Binary fidelity, executable mode, missing blobs, unsafe paths, links, gitlinks and case collisions. |
| Ignore policy | Nested exclusions/negation, tracked ignored files, host/global excludes ignored, mandatory ignored files fail. |
| Attribution | Default/explicit equal-valued license, added notices, shared files and external loading purpose. |
| Trust | Historical scripts and malicious Python import files inert; no fetch, filters, hooks or payload/tool execution. |
| Cleanup | Injected read/parse/matcher/cleanup errors; unchanged source files/index/refs and no successful partial output. |

Fixtures compare tracked/untracked bytes, index and refs before/after, not merely `git status`.
Temporary contexts disappear on ordinary success/failure. Injected cleanup failure suppresses
success and reports the condition without publishing source data.

## Platform and Completion Evidence

This feature's verification is complete for the observed Linux dev-container execution path.
On 2026-10-27 the maintainer permanently waived native Windows verification (T038): Python
tooling stays in the dev container, without Windows host provisioning. Native Windows behavior
remains unverified and no native Windows support is claimed. Static checks do not prove runtime
safety, Windows semantics, native discovery or redistribution rights.

Update existing skill guidance after observing implemented behavior. Task generation and analysis
precede implementation; no task list is generated by this planning command.

## Observed Checkpoints

- Synthetic fixture setup: 4 passed, 0 failed.
- Shared process/isolated Python checks: 4 passed, 0 failed after observing 3 expected initial
    failures; the existing sanitized-failure check already passed.
- Snapshot boundary and fixtures: 15 passed, 0 failed after implementing inspection and repairing
    path-array enumeration and a fixture that had omitted a force-added ignored external file.
- Required-preview checkpoint: 8 passed, 0 failed after implementing the public API and repairing
    conditional notice-array handling. This is not completion of optional or provenance review.
- The first metadata/preparation regression batch had 113 passed and 1 failed. Its explicit
    self-preparation fixture bundle omitted the extracted helper; the corrected case passed alone.
    The subsequent complete runner passed: 76 metadata, 38 preparation and 23 inventory tests,
    zero failures and nonzero counts in each suite.
- Optional-attribution checkpoint: 7 passed after observing 2 missing-decorator failures; the
    complete inventory suite then passed 30 tests, zero failures. Invalid optional requests and
    selected/unselected cycle rules retain existing validator outcomes.
- Declaration/safety checkpoint: 17 passed after repairing I/O error classification and canonical
    accepted root spellings. The full inventory suite then passed 47 tests, zero failures. It covers
    inherited/equal/different license sources, all five file-reason kinds, indexes, loading purposes,
    mixed shared ownership, ignored/missing mandatory declarations, injected read/validation/matcher/
    cleanup failures, moving refs, gitlinks, collisions, unsafe names and inert configured tooling.
- Final targeted safety/default cases: 3 passed, 0 failed out of 49 discovered. These verify the
    invoked tool's repository default from another working directory, actual hook/filter sentinels
    remaining inert and failure for a missing local blob without working-file fallback.
- Owning skill structure, discovery frontmatter, local links and maintenance checks: 4 passed,
    0 failed, using the `SkillName` Pester container data rather than a name filter.
- Committed pilot previews at current `HEAD`: required-only selection produced 1 component and
    6 files; explicit `module-composition` produced 2 components and 14 files. Shared notice owners
    matched, repeated JSON was identical, and source bytes, index, HEAD, branch, refs and local
    configuration were unchanged.
- Complete Linux focused gate: 76 metadata, 38 preparation and 49 inventory tests passed,
    163 total, with zero failures, skips or zero-test suites. Installed versions were
    PowerShell 7.6.9, Pester 5.7.1, Git 2.56.0, Python 3.13.5 and PyYAML 6.0.3.
- T039: editor diagnostics are clean for changed scripts, tests and guidance. Static parsing
    passed for all eight feature PowerShell files without executing them. After explicit approval
    for container-only setup and scoped lint, isolated pre-commit 4.6.2 ran the root configuration
    through the shared wrapper against all 17 feature files: six applicable hooks passed and five
    hooks skipped because no selected files matched their types. No files were modified.
- Tracked `git diff --check` and whitespace/final-newline/150 KiB checks across all 17 changed
    or new feature-owned files passed. These checks do not substitute for configured hooks.
- T038 is permanently skipped by maintainer decision; native Windows execution remains unverified.
    This is a waived check, not a passing result. No cross-platform support claim,
    packaging, installation, version preparation, publication or source Git mutation is implied.
- No Spec Kit post-implementation extension hooks were configured. T039 provisioned only the
    approved container lint runtime and hook dependencies; no Windows host setup, test reruns,
    Docker builds, Git hook installation, commits, tags or pushes were performed for this gate.
    All feature tasks are closed: 39 completed and T038 permanently skipped. Configured scoped
    lint is complete; no native Windows verification is implied.

## Requirement Accounting

Coverage below refers to implemented behavior and the observed Linux synthetic/pilot checks,
not native Windows verification or rights clearance. T039's static/lint evidence is recorded above.

| Requirement | Implementation and evidence |
| --- | --- |
| FR-001 | Existing validator owns explicit/default/repeated roots and optional request validation. |
| FR-002 | One resolved commit supplies all blobs; historical, dirty, deleted, moving-ref and missing-object cases exercise the boundary. |
| FR-003 | Captured trusted validator, strict reader and schemas validate every opted-in record; historical tooling/imports stay inert. |
| FR-004 | Chains, required descendants, explicit nested optionals, cycles and diamonds verify exact selected closure. |
| FR-005 | Validated identity/version, native paths, every reaching root and active incoming edge are asserted. |
| FR-006 | Committed regular files and modes are inventoried; snapshot ignores, mandatory eligibility and unrelated exclusions are checked. |
| FR-007 | Defaults, explicit equal-valued overrides, additive notices and external loading purposes retain declaration sources. |
| FR-008 | Unique paths retain all owners and the five distinct inclusion-reason kinds, including mixed internal/external cases. |
| FR-009 | Invalid requests, validation, unavailable input and cleanup failures emit sanitized categories without partial JSON. |
| FR-010 | Ordinal output is checked against reordered requests and repeated identical pilot JSON. |
| FR-011 | Fixture and pilot state snapshots remain unchanged; payload/filter/hook sentinels stay inert, Git transports are disabled and scratch cleanup is exercised. |
| FR-012 | Successful output explicitly excludes local edits and disclaims package, immutable provenance, rights and delivery approval. |
| SC-001 | Required, optional and declaration fixtures assert exact expected component/file membership, not counts alone. |
| SC-002 | Shared-path assertions retain source commit, every owner and every distinct declaration/edge reason. |
| SC-003 | Required chains and nested explicit selections include their exact closure without unselected optionals. |
| SC-004 | Invalid-selection, missing-source, injected-failure and cleanup cases reject partial success. |
| SC-005 | Before/after bytes, index, HEAD, refs and configuration checks cover success and failure; no delivery action is exposed. |
| SC-006 | Commit, effective declaration sources and limitations are directly inspectable in the returned object and JSON. |
| SC-007 | Repeated and reordered requests retain identical membership, reasons and deterministic review order. |
