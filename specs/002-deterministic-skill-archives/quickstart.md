# Validation Guide: Deterministic Skill Archives

**Status**: Implemented and verified on the Linux runtime tuple below. Scoped configured lint,
the 245-test convergence regression and the earlier separately approved real pilot/rebuild passed.
No installation, publication, version change, commit or push was performed by this implementation.
No archive builds or runtime tests were performed during planning.

## Prerequisites And Approval

Setup inspection observed Linux with PowerShell 7.6.9, CPython 3.13.5, Git 2.56.0,
PyYAML 6.0.3 and Pester 5.7.1. The selected existing interpreter is the Specify-managed
Python, passed explicitly through `-PythonPath`; no prerequisites were installed.
Synthetic test execution (including expected failures and injected faults) is approved for
this implementation session. Real pilot archives still require separate approval and destinations.
This is prerequisite evidence only, not archive or cross-runtime verification.

The setup syntax checks passed. The approved setup smoke check passed 3 tests with 0 failures
and 0 skips: inert PowerShell loading, inert isolated Python import, and committed temporary
fixture creation with complete helper-bundle copying. No archive construction was exercised.

## Observed Synthetic Evidence

The required-only gate initially passed 15 tests, then the independent CLI/header/rebuild/limit gate
passed 22. The completed archive suite passed 71 tests, with 0 failures and 0 skips. Checks observed:

- One root, required chains/diamond deduplication, independently required optional overlap,
  optional-only transitive exclusion, shared notices and external instruction purposes.
- Exact committed binary, empty, Unicode-content and CRLF bytes; executable modes; dirty/staged/
  deleted-local/untracked state excluded. Source files, index, HEAD, refs and local configuration
  stayed unchanged on success and source refusal. Existing optional preview still includes explicit choices.
- Independent raw local/central ZIP header checks, CRC/size/mode/date/flags/order and no extras,
  comments, descriptors, encryption or ZIP64. Manifest shapes, parsed attribution, content SHA-256
  and detached ZIP digest matched; synthetic byte tampering changed the hash.
- Complete ZIP bytes matched after changing output/caller directory, locale, timezone and umask.
  Eligible committed content changes and trusted builder-byte changes produced distinct evidence.
  Canonical JSON and conservative size/name/member preflight boundaries passed without large allocations.
- Unsafe/existing destinations and source-contained scratch were refused. Twenty-six injected
  creation/write/close/sync/hash/staging/finalization and interference cases suppressed success;
  foreign content, replacements, changed bytes and hardlinks were preserved. PowerShell scratch
  cleanup failure suppressed success. Controlled reservation contention produced one winner;
  killed-process marked and unmarked remnants were refused without modification.
- Fail-closed process/network tripwires detected synthetic forbidden attempts, then allowed a build
  without downloads, provisioning, install, version preparation, publication or historical code execution.
  Unsupported runtime simulations were refused before reservation, not treated as native support tests.

This evidence applies to Linux, PowerShell 7.6.9, CPython 3.13.5, Git 2.56.0, PyYAML 6.0.3 and
Pester 5.7.1 only. Native Windows, other Python implementations and cross-version byte equivalence
are not verified. Existing inventory filename restrictions remain unchanged. The root npm test
command also instruments unrelated container scripts; its reported 0% coverage is not archive
coverage and is not used as an archive acceptance claim.

## Convergence Follow-Up

On 2026-10-28, execution of the T041-T043 synthetic checks was separately approved, including the
expected failing baseline, focused archive/inventory checks and final four-suite regression.
No additional real pilot builds or prerequisite installations were authorized or performed.

T041's copied-bundle fault retained inventory-owned scratch and confirmed the public archive error
omitted its recovery path: 71 archive tests passed and the new assertion failed. After fixing the
owning inventory helper's sanitized Cleanup message, the identical configured npm archive check
passed 72 tests, with 0 failures and 0 skips. The regression verifies the exact retained location,
no raw injected diagnostic or success digest, no success output, no destination and unchanged caller
state. Its harness deliberately removed only the scratch directory recorded by that synthetic fault.

T042's configured npm archive check passed 74 tests, with 0 failures and 0 skips. After fixture HEAD
advanced, rebuilding the older full commit reproduced the original complete ZIP bytes/digest and
older notice bytes while preserving the newer working file and caller state. A separate disposable
fixture lost its required loose notice blob before invocation: the archive failed with Inspection,
no success output/digest or destination, the object stayed missing and caller state stayed unchanged.
A self-validating Git tripwire refused remote/mutating commands; the existing isolated Git boundary
also disables lazy fetching and transports. The changed-blob case now checks both exact member byte
sequences and differing per-member SHA-256 values, not just the final artifact digest.
T043's final configured npm regression passed 245 tests: 84 metadata, 38 preparation, 49 inventory
and 74 archive, with 0 failures, 0 skips and nonzero counts in all four suites. The saved task ledger
is reconciled to 43 completed tasks and no pending tasks, using the original approved evidence and
the targeted convergence checks above. No unresolved recovery/source-check obligation is closed
merely because an aggregate count passed.

Pre-PR review found that the saved ledger still had T004-T040 unchecked despite the completion
record above. Those 37 markers were reconciled against the recorded implementation and acceptance
evidence; task descriptions were unchanged. A saved-file check verified exactly T001-T043 completed,
with no pending or duplicate task IDs. No archive tests or real pilot were rerun for this bookkeeping
correction; the 245-test result remains the previously recorded execution evidence.

The follow-up review covers all 15 functional requirements and 6 success criteria using the
existing traceability table plus the new targeted assertions, not aggregate counts alone. Required-only
membership, deterministic headers, evidence and detached integrity remain covered by the existing
cases; T041 closes retained-path recovery in FR-010/FR-011 and SC-004, while T042 strengthens frozen
source and changed-member evidence in FR-005 and SC-005. Optional preview remains independent.
All five constitution principles retain their existing owners and boundaries: no new metadata
authority, discovery change, consumer state, platform claim or delivery approval is introduced.

A malformed runtime probe stopped before starting tests and was corrected. An initial final-regression
attempt was then interrupted by persistent-terminal reuse before it completed; neither attempt is a
passing gate. The approved rerun completed with the results above. Source/test editor
diagnostics are clear, and scoped configured pre-commit passed six applicable hooks with five
unmatched hooks skipped, without installation or formatter changes. The retained real pilot below
belongs to its recorded original builder bytes, not the updated inventory helper; no new real pilot
was built during this follow-up. The synthetic cleanup-fault harness removed its own recorded scratch.

Customization feedback: no new authority wording is needed. The owning skill already requires
retained-path recovery diagnostics, frozen-source evidence and explicit test approval. The nested
cleanup fix applies that existing rule rather than creating an archive-specific duplicate.

## Final Gates And Pilot

On 2026-10-27, the focused runner executed 84 metadata, 38 preparation, 49 inventory and 71 archive tests:
242 passed, 0 failed and 0 skipped, with nonzero counts in all four suites. Source/test/runner
editor diagnostics were clear. Three existing Markdown fragment-link diagnostics persisted;
the referenced files/headings exist, so no unrelated link rewrite was made.

Configured scoped pre-commit passed all six applicable hooks; five unmatched hooks skipped.
The EOF fixer normalized only final newlines in the three new source/test files; single-LF
endings were checked and the identical hook selection passed on rerun. No prerequisites installed.

The real pilot used `patterns-ports-and-adapters` version `1.0.0` at source commit
`39c4c7c35e30c450c87c06888aeb987183e04066`. Both separately approved new destinations were retained:
`/tmp/skill-archive-pilot-20261027-a` and `/tmp/skill-archive-pilot-20261027-b`. Each contains exactly
the ZIP/checksum pair; neither was installed, published or automatically deleted.

Both ZIPs are 39,800 bytes and compare equal in full with `cmp`. Their independently calculated
SHA-256 is `bebe96238427326d6dfcb60a6674a599775754ff1931463110d6724fbf306e8a`.
Both detached checksum records exactly match the hash, two spaces, `package.zip` and LF.
Each ZIP has seven members: generated manifest, the root's four native files, its external C#
instruction and LICENSE. The manifest has one component and zero optional selections; the optional
module-composition skill and its payload are absent.

The pilot builder used PowerShell 7.6.9, Git 2.56.0, CPython 3.13.5 and PyYAML 6.0.3. All nine
captured trusted input paths and SHA-256 values are retained in each embedded `Builder.Files`.
The entry-point digest is `dcb6b3e1e761493ce43610ecaaa40da6a5fa589e70c09ad76227d65dc5d71a86`;
the writer digest is `1547dee8cee995772c80aa29d1a5a9330044799f7be1a37a763174efdec6693a`.
These bind invoked implementation bytes separately from the source commit; future builder edits
change this input tuple and do not retroactively describe the retained pilot as built by new bytes.

No unintended recovery material remains from the synthetic scenarios; their deliberately retained
foreign/replacement/crash fixtures were removed only by their owning temporary test harnesses.
Caller pilot artifacts remain. The root README catalogue was reviewed: its existing validation
description is still accurate and was left unchanged rather than expanding an unrelated catalogue.

The final requirement audit maps FR-001 through FR-015 and SC-001 through SC-006 to the observed
cases above: exact required membership, frozen source, independent integrity/attribution, complete
byte rebuilds, safe refusals/cleanup and self-validating no-side-effect checks. Constitution review
found no exception: the existing skill remains the owner, native/optional-preview usage remains,
generated evidence is separate from unchanged authored metadata, and tests/pilots used explicit
approval. The distribution ADR remains In Progress. Native Windows, extension loading, signatures,
redistribution approval and cross-runtime byte equivalence remain unverified, not accepted skips.

Customization feedback was applied to the owning skill's maintaining section: complete bundle
capture, CPython ZIP drift, ownership/handshake fault coverage, tripwire arming order and structured
JSON comparisons. No competing authority or new metadata schema was introduced.

- Use the existing Linux dev container with PowerShell 7.4+, CPython 3.11+, Git and PyYAML 6.0.3.
  Supply an already installed interpreter; do not install prerequisites as part of these scenarios.
- Import the repository-pinned Pester 5.7.1 when running its existing synthetic test runner.
- Obtain explicit approval before running any tests or archive scenarios. Keep synthetic Git
  mutations in temporary fixture repositories, never the source checkout.
- Choose an existing trusted temporary parent outside the repository and Git directories. Each
  build requires a new destination; do not automatically delete or reuse existing output.
- Review the [public contract](./contracts/archive-build.md) and
  [evidence model](./data-model.md). Format and safety details belong there rather than in examples.

## Build A Required-Only Pilot

After implementation and approval, use an existing opted-in root without optional selections:

```powershell
$repo = (Get-Location).Path
$python = '/path/to/existing/python'
$sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
$parent = [IO.Path]::GetTempPath()
$firstDestination = Join-Path $parent 'skill-archive-example-a'
$secondDestination = Join-Path $parent 'skill-archive-example-b'
$script = Join-Path $repo '.github/skills/skill-library/scripts/Invoke-Archive.ps1'
$first = & $script -RepoRoot $repo -SourceRevision $sourceCommit `
    -SkillName patterns-ports-and-adapters -OutputDirectory $firstDestination `
    -PythonPath $python | ConvertFrom-Json
```

Expect one success object only after cleanup. The output directory contains exactly `package.zip`
and `package.zip.sha256`. The ZIP contains `manifest.json` followed by required-only payload
members under `payload/`. The pilot's optional module-composition relationship must not add its
target or its files. Advisory optional declarations can still appear in the root's original sidecar.

Inspect without extracting or executing payloads:

```powershell
& $python -I -B -m zipfile -l $first.ArchivePath
$firstHash = (Get-FileHash -LiteralPath $first.ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($firstHash -cne $first.ArchiveSha256) { throw 'Archive digest mismatch.' }
$expectedChecksum = "$firstHash  package.zip`n"
if ([IO.File]::ReadAllText($first.ChecksumPath) -cne $expectedChecksum) {
    throw 'Detached checksum mismatch.'
}
```

During approved synthetic validation, independently read all members and compare the manifest's
source paths, sizes, content digests, modes, reasons and declarations against the known fixture
and required-only inventory. Verify exact headers as well as extracted bytes. Do not treat successful
listing as proof of header normalization, rights clearance or extension installation compatibility.

## Rebuild And Compare

Run the identical input tuple with the second destination:

```powershell
$second = & $script -RepoRoot $repo -SourceRevision $sourceCommit `
    -SkillName patterns-ports-and-adapters -OutputDirectory $secondDestination `
    -PythonPath $python | ConvertFrom-Json
$secondHash = (Get-FileHash -LiteralPath $second.ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($firstHash -cne $secondHash) { throw 'Rebuild digest mismatch.' }
& cmp -- $first.ArchivePath $second.ArchivePath
if ($LASTEXITCODE -ne 0) { throw 'Rebuild bytes differ.' }
```

Repeat synthetic builds in independent temporary contexts with different times, output paths,
locales and umasks. Do not add a sleep: timestamp variation can be simulated in fixtures or observed
across independent invocations. Dirty/staged/deleted-local files must not change a pinned-commit
build. A changed eligible blob must change the member bytes and archive digest. Record exact tool
and runtime identities; changing them changes the complete input tuple, not just the destination.

## Focused Synthetic Gate

After the archive suite is added to the existing runner, request approval for its focused gate
and the affected existing suites. The planned repository command is:

```powershell
& (Join-Path $repo '.github/skills/skill-library/scripts/Invoke-Tests.ps1') `
    -PythonPath $python
```

Require nonzero counts for metadata, preparation, inventory and archive suites, with actual
failures/skips disclosed. Do not invent future counts. Required coverage includes:

- Required chains/diamonds, shared notices, optional-only exclusion and required/optional overlap.
- Missing/multiple/repeated roots and rejected optional selections, including an empty selection.
- Dirty and historical source, invalid catalog records and missing local objects without fetching.
- Binary/empty files, executable modes, Unicode names and line-ending byte preservation.
- ZIP order, fixed headers, CRC, exact contents, canonical manifest arrays and detached checksum.
- Existing empty/nonempty directories, files, dangling links, linked ancestors, missing parents,
  source/Git containment and prefix-lookalike directories; caller-owned entries stay untouched.
- Competing destination reservations; exactly one winner, no overwrite or adoption of partial output.
- Injected create/write/close/sync/hash/finalization/cleanup failures; no partial success result.
- Foreign entries, replaced paths and changed content before rollback; preserve ambiguous files.
- Interrupted builds and retry refusal, including leftover directories without incomplete markers.
- Source files, index, HEAD, refs and local Git configuration unchanged by successful/failed builds.
- Unsupported platforms rejected before output reservation; no test implies Windows support.

## Static Checks And Evidence

After implementation, run editor diagnostics and the configured root pre-commit hooks on the
changed files using the [shared lint workflow](../../.github/skills/pre-commit-management/SKILL.md).
Review formatting changes and rerun once if needed. Do not replace configured lint with a direct
linter. Public content must satisfy the existing privacy boundary before any future commit/push.

Record exact runtime/tool identities, selected source commit/root, suite counts, byte/header/digest
results, optional exclusion, fault-injection outcomes and caller-state evidence here after approved
execution. Keep planned and observed results separate. The previous feature's Windows waiver does
not close this feature's platform gate or establish native Windows compatibility.

## Planning Evidence

- Spec Kit setup resolved this feature and created the plan scaffold on 2026-10-27.
- Local implementation reads and two read-only research tasks informed the design; no runtime
  archive implementation or tests were executed.
- The plan's constitution gates pass at design level. No component versions, Git refs, consumer
  installs or publication state were changed by planning.
- Scoped document lint and local-link verification are reported separately at planning completion;
  they do not prove the archive contract at runtime.
