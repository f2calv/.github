# Validation Guide: Bounded Workspace Installer

**Status**: The bounded installer has completed real root/optional installation and a retained real
child-loss scenario under the owner's 2026-10-29 authorization. Integration and all 366 final adjacent
baseline regression tests passed; the later PR review repairs passed ten focused checks below.
Current-consumer editor acceptance remains pending. The earlier synthetic checkpoint passed
107/107 workspace and 49/49 inventory tests; it is not the final regression after runtime fixes.
Obtain separate approval for tests,
real builds, hosting, disposable consumers, installs, commits and pushes; root implementation is not
permission to use a real consumer before those gates.

## Prerequisites

- Linux, PowerShell 7.4+, Git and an existing CPython 3.11+ interpreter with PyYAML 6.0.3 and Spec Kit CLI 1.2.3.
- Existing initialized built-in Copilot skills-mode disposable consumer outside the source checkout.
- Trusted source commit, generated local catalogs and prebuilt command-only extension ZIPs matching
  that commit; no new downloads or builds are required by the installer.
- A synthetic root with required resources, at least two optional offers, one nested optional offer
  and overlapping required resources. Build fixture artifacts only after separate approval.
- Explicit permission for the chosen disposable consumer path. Do not create a secondary clone or
  Git worktree without the separate approval required by the workspace rules.

Use the [contract](./contracts/workspace-install.md) for parameters and the
[data model](./data-model.md) for fingerprints, conflicts and recovery states. The placeholders below
are synthetic absolute paths; replace them with approved existing locations before running anything.
The selected skill/optional keys must exist in the chosen synthetic metadata.

## Focused Automated Checks

After explicit test approval, run the adjacent suite through the existing root
runner from the source repository root:

```bash
npm --prefix /workspace/source run test:ps -- \
  -TestPath .github/skills/skill-library/scripts/tests/Invoke-WorkspaceInstall.Tests.ps1
```

Use the repository-pinned Pester 5.7.1 and existing interpreter-selection convention; no package
installation or full-suite expansion is implied. Require nonzero discovered/executed test counts,
zero failures and no hidden prerequisite skips. Fixture installers/fault injectors must not contact
services or mutate a real consumer. The focused suite should cover these discriminating cases:

| Scenario | Expected Evidence |
| --- | --- |
| Root-only preview | Exact required closure, all offers unselected, no consumer/profile writes |
| Select one of two offers | Separate optional extension, nested offer stays off, declined ZIP unopened |
| Overlapping closure | Both payloads complete; separate ownership; root ZIP hash unchanged |
| Invalid selection/graph | Exact pin, key, cycle and metadata blockers; no hyperlink inference |
| Unavailable/ambiguous artifact | No fallback/rebuild/download; precise catalog/artifact blocker |
| Corrupt identity/content/notices | Refusal before delegation; every expected member accounted for |
| Changed approval inputs | Source/tool/catalog/archive/runtime/workspace/registration changes refuse |
| Equivalent unordered inputs | Argument/record permutations preserve the fingerprint under the model's ordering rules; bound byte/index/execution changes invalidate it |
| Unresolved prior operation before root apply | Preview is blocked; apply refuses before reservation/delegation and preserves prior evidence, including state introduced after approval |
| Occupied or linked targets | Preserve exact version, orphan payload, command-only and registry-only cases |
| Unsupported runtime effects | External/changed adapter, hooks, modes, bytecode and scratch escape blocked |
| Fault/cancel around each boundary | Accurate Verified/Failed/Unknown/Pending subsets and retained evidence |
| Abrupt process termination | Stale intent/lock blocks retry; no automatic deletion or resume |

The subprocess/install spies must be armed and their invocation counts asserted, not silently skipped
when an interpreter is unavailable. Verify strict JSON/YAML parsing and same-stream byte verification.

## Read-Only Preview

Approve use of prepared local inputs and capture a before snapshot
of consumer files, modes, runtime state and relevant profile guidance. Use a separate source worktree
status/hash check to prove canonical files remain untouched; do not create a new checkout for this.

```powershell
$Installer = '/workspace/source/.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1'
$Inputs = @{
    RepoRoot = '/workspace/source'
    SourceRevision = 'HEAD'
    SkillName = 'example-root'
    WorkspacePath = '/workspace/consumer'
    CatalogPath = @('/workspace/artifacts/root/catalog.json', '/workspace/artifacts/peer/catalog.json')
    ArtifactDirectory = @('/workspace/artifacts/root', '/workspace/artifacts/peer')
    PythonPath = '/workspace/tools/bin/python'
}
$Preview = & $Installer @Inputs
$Preview | ConvertTo-Json -Depth 100
```

Expect Ready true, one root extension, literal versions and digests, exact intended write paths,
reasons, overlaps, optional offers and a nonempty fingerprint. Compare the before snapshot: zero
consumer/profile mutation, cache, lock, receipt or extraction. Repeat with missing local artifacts:
expect Ready false, Fingerprint null and no network call or setup attempt. Obtain a fresh preview
after resolving a blocker; never reuse an old fingerprint.

## Explicit Optional Selection

**Implemented with synthetic validation.** Choices are exact active `component-id/selectionKey` values;
duplicate supplied, unknown and inactive keys refuse. Offers default off, including newly exposed
nested offers. Multiple active declarations can select one target with all reasons retained; duplicate
dependency edges within a declaration remain invalid.

Use the exact offered selection key from the synthetic fixture; include the selected peer's existing
catalog/artifact directory. A declined peer needs no local artifact and must never be opened.

```powershell
$Inputs.OptionalSelection = @('example-root/related')
$SelectedPreview = & $Installer @Inputs
$SelectedPreview | ConvertTo-Json -Depth 100
```

Expect a different fingerprint and exactly two extension roots: the original root and selected peer.
Each has its own required-only inventory and intended command. The root ZIP digest is unchanged,
shared source resources appear beneath both extension-owned trees and newly exposed optional offers
remain unselected. The original root executes first, followed by distinct selected optional IDs sorted
ordinally; at most sixteen roots are allowed. Review the complete revised preview before requesting
apply. A root-only fingerprint cannot authorize this selection.

## Approved Apply And Installed Verification

**Root and explicit optional apply are implemented and verified through the real pinned runtime.**
Each consumer still requires its own approval; the retained demo is not authority for another workspace.

Obtain explicit approval for that exact ready fingerprint and disposable workspace. Keep the same
inputs. Do not add optional choices or change paths while reusing approval.

```powershell
$Reviewed = & $Installer @Inputs
$Reviewed | ConvertTo-Json -Depth 100
# Only after approval of this complete ready result:
$Applied = & $Installer @Inputs -Apply -ReviewedFingerprint $Reviewed.Fingerprint
$Applied | ConvertTo-Json -Depth 100
```

Expect State Completed only after every selected root is Verified and final evidence is flushed. Inspect runtime
registration, the generated Copilot skill, installed identity/version, every canonical byte/mode and notice, plus
the operation receipt. Compare unrelated consumer files/modes, profile guidance and source bytes to
the before snapshot. Observe real extraction/temp/bytecode paths under the declared operation scratch;
an environment-setting assertion alone does not close confinement acceptance. No HTTP hosting is used.

Change one approved input between preview and apply in a fresh disposable scenario. Expect refusal
before upstream installation. Repeat against occupied targets, including the same exact version and
command/registry orphans: preserve all existing content; do not use force or adopt the installation.

## Failure, Cancellation And Reconciliation

**The synthetic fault/termination matrix is exercised.** Coverage includes cancellation at internal
receipt boundaries, actual disposable runtime-child SIGKILL, malformed output, partial observation,
receipt-write failure and ordered synthetic entries. It does not demonstrate actual upstream
execution, whole-orchestrator termination, machine crash or power-loss recovery.

After explicit approval, use the synthetic harness to fail/cancel before the first delegation, between
extensions, during registration, during receipt writes and after an upstream success but before
verification. Also terminate a disposable child process after durable Attempting evidence. Do not inject
faults into a real maintained workspace.

Expect stop-on-first-failure, no total success and no second extension after an unresolved first one.
A previously verified extension stays recorded as Verified; uncertain outcomes remain Unknown. Check
recovery locations and preserved caller edits. A subsequent apply must block on stale lock/incomplete
evidence. Inspect and preserve that evidence; use separately approved manual/runtime reconciliation,
not an installer cleanup/resume flag. A clean preview is still required, and completed installations
remain blockers to reapplying the same root.

## Editor Runtime Gate

In the approved disposable consumer, refresh editor discovery as needed and select the registered
native `/speckit-<id>-load` command. Do not attach the loader manually as a substitute for discovery.
Observe actual guidance reads beneath the installed extension's `resources/library` tree, including
declared instructions and relevant references. No source-checkout, user-profile or declined-skill
fallback is acceptable. A loader automatically attached by the editor need not appear as a separate
file-tool read; distinguish this from subsequent canonical guidance reads.

Record registration, discovery, invocation and installed-only reads as separate gates. Label evidence
as captured trace or owner observation. If discovery or read observation is unavailable, leave that
gate unverified; successful copying or a manual file read cannot pass SC-006.

## Acceptance Record

### Read-Only MVP Evidence

Test approval covered only the focused synthetic workspace suite and neighboring inventory regression
suite, including expected-failure checks and reruns. No services, downloads, real consumer operations,
production archive builders or artifact publication were authorized or performed.

- Observed prerequisites: Linux, PowerShell 7.6.9, Pester 5.7.1, CPython 3.13.5, PyYAML 6.0.3,
  Spec Kit CLI 1.2.3 and Git 2.56.0. The runtime probe checked the archive API and installed module
  bytes against distribution RECORD hashes; ready previews include participating source/tool hashes.
- The approved 25-case red baseline exposed 14 orchestration failures after fixture repairs; all 25
  passed after implementation. Expanded 41-, 46- and 47-case runs passed with zero failures/skips.
- Final saved workspace suite: 48 discovered/executed, 48 passed, zero failed/skipped/not run. This
  includes complete Prepared/Running/Attempting receipts and inconsistent Completed evidence.
  Neighboring inventory regression: 49 discovered/executed, 49 passed, zero failed/skipped/not run.
  Both ran through the configured root npm/Pester runner with the existing interpreter.
- Validation used saved on-disk inputs. An intermediate editor-buffer-only test addition was not
  counted as executed; after Save All, discovery increased from 47 to 48 and the full suite passed.
  The temporary editor task used for Save All was removed.
- Source and consumer snapshots compare bytes, executable modes and Git state before/after ready,
  corrupt-input and unresolved-state previews. Dirty/staged/deleted/untracked working files do not
  replace committed inputs. A binary resource and an ordinary Markdown link are included.
- Self-tested tripwires first prove installer construction, network, extraction, writes and declined
  ZIP access would be detected, then assert zero calls across catalog, selected-ZIP and consumer
  inspection. Catalog URLs remain inert. Synthetic ZIPs are constructed directly by the harness.
- Private foundation tests refuse preview contexts, verify 0700 directories/0600 evidence, flush a
  Prepared-to-Running receipt replacement and reject foreign same-byte inode replacement. Those
  synthetic writes are not public apply or real upstream installation acceptance.
- Canonical fingerprint tests cover a fixed UTF-8 golden encoding/hash, non-ASCII/case ordering,
  numeric authored indexes, recursive ties, unordered argument/evidence permutations and null/array
  distinction. Changed raw catalog/archive bytes or execution positions change or block approval.
- Config prediction includes the installed-extension list even without declared hooks. Comment-bearing
  configuration, duplicate keys, external integration state, changed adapters and collateral chmod
  refuse readiness without altering their evidence.
- Configured scoped offline pre-commit checks passed after EOF normalization. Editor diagnostics were
  clean. Ruff and mypy are unavailable; Python formatter/linter and strict type checking remain
  unverified. No prerequisite installation was attempted.

At the MVP checkpoint, public `-Apply`, nonempty `-OptionalSelection` and preview approval tokens were
blocked. The root-only increment below supersedes only the apply restriction. Real
artifact builds, upstream installation/verification, process-cancellation/confinement, optional apply,
Windows support and editor discovery/invocation/installed-only reads have not been demonstrated.
No feature implementation commit or push was made.

### Root-Only Apply Evidence

Separate approval covered T021-T030 and focused synthetic workspace/inventory tests, including red
baselines and reruns. No real manager construction, consumer install, network, package download,
artifact build, publication, commit or push was authorized or performed.

- The four new approval/refusal contracts first produced 48 passed/4 failed, then 52/52 passed after
  original-input recomputation. Ten new apply contracts produced 52 passed/10 failed before wiring.
  The first integrated run passed the same-stream success case (53 passed/9 failed); its nine retry
  assertions exposed guard ordering. Moving unresolved-state checks ahead of occupied targets gave
  62/62, then preservation/drift coverage gave 64/64. Reported cancellation added one case; both
  that run and the final diagnostic-tripwire rerun discovered/executed 65, all passed with zero
  failed/skipped/not run. The approved inventory regression discovered/executed 49, all passed,
  with zero failed/skipped/not run. Both used the configured root npm/Pester runner.
- The test child replaces ExtensionManager with a synthetic implementation, not a public installer
  switch. It asserts the same open stream verified by the bridge, one selected-archive open,
  offset zero, literal expected version, runtime 1.2.3, priority 10 and force false. It reads a durable
  Running/Attempting receipt before constructing the synthetic manager. Production uses only the
  upstream archive API; test extraction is confined to disposable synthetic fixtures.
- The synthetic child observes its private TMPDIR and an actual temporary-directory allocation
  beneath operation scratch. The host TMPDIR and source snapshot remain unchanged. This validates
  the synthetic child, not production launcher/upstream confinement or profile-write isolation.
- Completion checks every payload/notice byte and mode, exact command, literal version, registry
  mapping and UTC timestamp, predicted configuration and unrelated inspected state. A preexisting
  unrelated extension, command, registry entry and false auto-hook setting survive. Editing detached
  preview evidence cannot change recomputed approval. Completed receipts and empty 0700 scratch
  remain; the unchanged owned lock is released, but same-version reapplication still refuses.
- Corrupt selected ZIPs, stale catalog approval and unresolved state introduced after approval refuse
  before reservation with unchanged consumer evidence. Reserved-state drift stops before an
  installer call while retaining a receipt/lock and reporting pending root, mutation and recovery
  locations. Existing private-writer checks reject foreign same-byte evidence replacement.
- Ten synthetic faults cover notice bytes, missing command, literal-version drift, registration,
  extra payload, mode, unrelated content, warning, runtime exception and reported KeyboardInterrupt.
  The reported interrupt yields Cancelled operation state and an Unknown extension, not completion.
  None reports completion;
  partial files and the lock remain, and retries refuse unresolved evidence without further calls.
  The warning fixture emits stdout and stderr markers before warnings-as-errors interrupts it;
  none of that content, exception content or tracebacks reaches JSON or stderr. There is no automatic
  rollback, adoption, deletion or resume.
- Inspection verifies the pinned runtime source/RECORD identities; actual upstream constructor,
  extraction/registration and full fault/cancellation/termination behavior are unperformed gates.
  Ruff/mypy remain unavailable and unverified. Configured scoped offline lint and editor diagnostics
  are clean; no new dependencies were installed. The root runner also prints unrelated container
  workflow coverage below its target; no workspace coverage gate is claimed from that output.

Record source commit, trusted tool/runtime versions and hashes, local artifact digests, approved
fingerprint, synthetic case counts, actual affected paths, per-extension outcomes and observation
method. Do not publish local machine details, credentials or private consumer identifiers.

### Failure-Hardening Evidence

Separate approval covered T031-T038 synthetic fixtures, expected-failure runs/reruns, disposable-child
termination and the neighboring inventory regression. No real install, download, production build,
consumer mutation, publication, commit or push occurred. The observed prerequisites remain those
listed above; no tools or packages were installed.

- Final workspace suite: 93 discovered/executed, 93 passed, zero failed/skipped/inconclusive/not run.
  Inventory regression: 49 discovered/executed, 49 passed, zero failed/skipped/inconclusive/not run.
  Both ran through the configured root npm/Pester runner in independent parallel jobs. These are
  synthetic acceptance checks, not a real-runtime readiness claim. The runner's unrelated container
  workflow coverage warning is not workspace coverage evidence.
- Test-first intent persistence produced 65 passed/1 failed, then 66/66 passed. The initial expanded
  matrix produced 78 passed/1 failed; subsequent observation checks exposed discarded readable paths
  and absolute-ancestor handling. The focused 11-case observation/termination run passed after repair.
  Ordered-state contracts produced 79 passed/5 failed before implementation. One later full run
  stopped without a summary and is not counted as passed. Targeted validation exposed wrapped
  cancellation classification (6 passed/1 failed), then passed 7/7 and the expanded 10/10 before the
  final 93-case run. Temporary focused wrappers are not a new suite or production interface.

| Boundary | Executed Observation |
| --- | --- |
| Before reservation | Same-version payload, local edits including mode, orphan payload, command-only and registry-only conflicts preserve the consumer snapshot; zero apply calls or operation evidence |
| Reserved/Prepared | Changed approved state stops before delegation with Pending root and retained evidence; failed Prepared receipt has no claimed durable step |
| Intent persistence | Failed Attempting and outcome writes leave Pending, zero runtime calls and the previous Prepared receipt |
| Cancellation | Prepared and validated boundaries remain Pending; cancellation after Attempting remains Unknown; no installer call in these three internal cases |
| Constructor/copy/registration | Constructor exception remains Unknown; reported copy/registration cancellation stops with Cancelled operation and Unknown root; readable partial effects remain observed |
| Child loss | SIGKILL before copy, after copy, after registry and after config but before verification; no clean response, Unknown root, retained intent/lock and blocked retry |
| Malformed/unreadable output | Truncated JSON triggers fresh inspection; a linked partial path gets explicit unknown presence without discarding readable present payload records |
| Verified/Completed persistence | A verified root stays Verified if its receipt or final completion write fails; last durable step remains Attempting or Verified when the outcome receipt also fails |
| Ordered next step | Verified first, Failed/Unknown second and Pending third; cancellation, next-target drift or failed second intent stop with the later entries Pending and only one call |
| Lock release | A same-byte foreign replacement is preserved; Completed receipt and Verified root remain evidence, but result is Unknown, exit 3 and retry is blocked |

The ordered fixture compares earlier verified file hashes and introduces an actual occupied next
target before revalidation. It uses private callbacks, not public optional selection or a
caller-edited approval. The production root path performs its full approved-state bridge revalidation;
the later optional evidence below exercises public multi-extension integration separately.

The synthetic child receives a disposable HOME/config directory containing profile guidance. Its
before/after bytes/modes/Git snapshot is unchanged on both success and failure. Source snapshots and
host TMPDIR remain unchanged in the stage matrix. The existing self-tested prohibited-operation
tripwires remain covered; raw diagnostic markers and tracebacks do not escape the child protocol.
Unknown paths are never converted into proof of absent writes, and no retry, recursive cleanup,
repair, uninstall or resume is invoked to resolve a fault.

Inspect and preserve receipts, owned evidence, scratch and partial runtime files outside the active
operation namespace before separately approved manual/runtime reconciliation. Require a fresh
clean-target preview afterward; completed targets remain occupied. There is no reconciliation,
delete, force or resume command and no atomicity or power-loss guarantee. Real upstream filesystem
effects, whole-orchestrator termination, editor acceptance and unavailable Ruff/mypy checks remain
unverified. Scoped cached offline lint passed and editor diagnostics were clean at that checkpoint.

### Explicit Optional Evidence

Separate approval covers T039-T046, scoped synthetic checks during development and one final workspace/
inventory regression in independent parallel jobs. No real manager/install, download, production build,
consumer mutation, publication, commit or push is authorized or performed.

- The first projection contract failed, then passed after forwarding explicit keys to the authoritative
  validator. The four core contracts initially produced 1 passed/3 failed with optional selection
  blocked; projection/preview wiring gave 3 passed/1 failed, then ordered apply gave 4/4 passed.
- The expanded optional matrix discovered/executed fifteen cases: fourteen passed and one invalid
  duplicate-edge fixture failed metadata validation. The repaired case uses two active declaring
  components, then passed its isolated one-case rerun. No validator rule was relaxed.
- The SC-003 synthetic case offers two peers, selects exactly one and leaves the other declined. It
  verifies two independent required-only artifacts at one frozen commit, unchanged root ZIP digest,
  retained source-path/hash overlap ownership, identical shared bytes in different physical files,
  two Verified entries and inactive nested offers. Self-tested installer/network/extract/write/ZIP
  tripwires report zero prohibited preview calls, including declined and nested ZIP access.
- Contracts reject duplicate supplied, unknown and inactive keys, stale root-only approval and a
  missing selected peer artifact without consumer mutation or a build/fetch fallback. Distinct target
  offers retain all reasons, including required/optional overlap across declarations. Sixteen roots
  are accepted and seventeen refused.
- Peer notice verification failure, constructor uncertainty and reported copy cancellation retain the
  Verified root, exact Failed/Unknown peer, evidence and blocked retry. Actual earlier-byte or next-target
  drift stops before peer delegation with the peer Pending and caller changes preserved.
- Final workspace suite: 107 discovered/executed, 107 passed, zero failed/skipped/inconclusive/not run.
  Inventory regression: 49 discovered/executed, 49 passed, zero failed/skipped/inconclusive/not run.
  Both ran once through the configured root npm/Pester runner in independent parallel jobs, using the
  existing interpreter and prerequisite versions recorded above. The root runner's unrelated container
  coverage warning is not workspace coverage evidence. No other regression suite was added or run.
- Six-file configured cached offline lint passed, with editor diagnostics clean. Real pinned-runtime
  execution, upstream interruption/confinement, editor discovery/installed-only reads and unavailable
  Ruff/mypy checks remain unverified. This evidence does not close the end-to-end acceptance gates below.

At that checkpoint T039-T046 were complete and work stopped before T047. The subsequent owner
authorization covers bounded completion, tests, real local builds, disposable consumer installation
and the editor demonstration below. It does not enable auto-commit/auto-push or public publication.

### Real Runtime Demo

On 2026-10-29 the owner authorized completion of the bounded installer for a working demonstration and
a reviewable PR, explicitly deferring broader distribution capabilities in the ADR. No new packages,
downloads, hosting, secondary checkout, authored version/pin changes, releases, commits or pushes were
needed. Existing Linux/PowerShell 7.6.9/CPython 3.13.5/PyYAML 6.0.3/Spec Kit 1.2.3 tooling was reused.

Trusted source commit: `71fab57257908a6b5b7a23057479c5f201699105`. The invoked local builder/verifier
identities are retained in generated evidence separately from that committed payload source.

Pinned runtime module SHA-256 identities from the real preview:

- `specify_cli/extensions/__init__.py`:
  `e40ca2690f20095b764a26f404c4e1f43d53696fc1c0b983801859c7d69115a1`.
- `specify_cli/integrations/copilot/__init__.py`:
  `db02b2657e27f0e14f72b247b2482bc6a5b700506d8e969e4d92e352e65100c7`.

| Extension | Version | Canonical Files | Extension ZIP SHA-256 |
| --- | --- | --- | --- |
| patterns-ports-and-adapters | 1.0.0 | 6 | `63af3bbdf85e6f53472ba99d7c005cf9300f11da0cbac84441746eeecd7b87a2` |
| patterns-monolith-modular | 1.0.0 | 10 | `7ef866e80ec8384305af35a147f1a23e55b4da97a8d7f0801f60bb0d745425ba` |

The root's exact optional key is `patterns-ports-and-adapters/module-composition`. Both extensions
retain their own required instructions/notices; the two shared source paths are not physically
deduplicated. This real graph has one optional skill and required files, not a required skill edge or
two optional offers. The synthetic SC-003 case above separately proves one-of-two selection, required
skill closure and nested offers remaining off. Neither case is substituted for the other.

- Real builds used the existing archive and extension entry points; both retained ZIPs were reused
  unchanged. Root-only and root-plus-peer previews were ready with different fingerprints and zero
  consumer changes. The selected preview fingerprint was
  `c0d33e876fa08ff4db42684bc052fdb56b9358f39eab2ed5a33e1ef9f19c9d59`.
- Actual acceptance exposed stock init-options/integration settings and generated Copilot manifests
  missing from the reduced fixture. The scanner now validates those pinned fields, safe recorded paths
  and hashes. Its focused stock-init contract failed first, then passed, including hash-mismatch refusal.
- Real producer manifests include GeneratedMembers/Limitations; the fixture and verifier now require
  the full shape. Focused stock/root preview checks passed 2/2. Actual Spec Kit installation preserves a
  `0700` extension root, not the fixture's `0755`; the preview and synthetic manager were corrected and
  focused stock/root/two-extension checks passed 3/3.
- The initial real root operation stopped on that mode mismatch with the peer Pending. Its consumer,
  Failed receipt and lock remain untouched; subsequent preview refuses OperationState without changing
  its tree. No repair, overwrite, adoption or retry installation was attempted there.
- A distinct fresh consumer installed both exact-version extensions through real
  `ExtensionManager.install_from_archive`. Both are Verified and the operation Completed, with final
  receipt flushed and owned lock released. All sixteen canonical files/notices, generated commands,
  modes, raw manifest hashes, registry entries and sequential configuration predictions passed checks.
- Source `.github` and inspected Spec Kit profile files/modes were unchanged. The unrelated consumer
  note and preexisting core commands survived. A same-version occupied preview refuses without
  changing the completed consumer.
- `strace` followed the actual isolated runtime processes. The two extraction children made 175
  observed file-mutating calls, all beneath the consumer; extraction temporary directories were beneath
  operation scratch. There were zero observed outside-consumer writes, internet connections or bytecode
  writes from those children. This is observed confinement for this run, not a hostile-writer guarantee.
- A third fresh consumer installed the real root, then an external local harness terminated the peer's
  actual isolated child after the receipt durably recorded root Verified/peer Attempting. The result
  retained root Verified and peer Unknown, preserved lock/evidence/partial paths and blocked another
  preview with OperationState without changing its tree. This tests child loss before a verified peer
  result, not a machine crash or proven interruption during upstream copying.

Final approved regression ran each suite once through the existing root npm/Pester runner, in
independent parallel jobs with the existing Spec Kit interpreter and pinned Pester 5.7.1:

| Suite | Passed | Failed / Skipped / Not Run |
| --- | --- | --- |
| Metadata validation | 84 | 0 / 0 / 0 |
| Version preparation | 38 | 0 / 0 / 0 |
| Inventory preview | 49 | 0 / 0 / 0 |
| Archive | 74 | 0 / 0 / 0 |
| Extension | 13 | 0 / 0 / 0 |
| Workspace installation | 108 | 0 / 0 / 0 |
| Total | 366 | 0 / 0 / 0 |

There were no inconclusive cases. Repository-configured scoped offline pre-commit passed, all 95
checked local links across ten owning/feature documents resolved, editor diagnostics were clean and
`git diff --check` passed. The root runner's unrelated container-coverage warning is not workspace
coverage evidence. Ruff/mypy and whole-orchestrator/power-loss behavior remain unverified; they are
not silently reported as passed. T053 is the only pending task: current-consumer native command
invocation and installed-only reads require actual editor observation. No commit or push was made.

### Foundation PR Close-Off

The owner authorized closing and merging this foundation on 2026-10-29 before implementing the
[revised ADR demo deliverables](../../docs/adr-0001-copilot-spec-kit-distribution.md#foundation-close-off-and-demo-scope).
The exercise closes at its verified boundary, not by marking T053 passed. Its per-extension editor
observation remains unperformed and does not replace the future shared-command acceptance.

Local pre-PR review identified and repaired three bounded issues:

- Preview now refuses selected-extension `.rescue-staging-<hash>` state before reservation. The pinned
  runtime can otherwise restore or delete that recovery tree. Completed and incomplete rescue cases
  both refuse preview/apply while preserving bytes/modes and creating no operation namespace.
- Canonical approval evidence is limited to 4 MiB before reservation, leaving request-envelope room
  within the existing 8 MiB bridge limit. Saved receipt reads use the existing 64 MiB evidence-file
  bound instead of the unrelated 4 MiB state-file default. Near-limit and oversized checks pass.
- The adjacent runner checks Pester's aggregate result and requires at least one passing case, so
  suite-level hook failures, skipped-only and empty suites cannot report success.

CI's library test workflow installs Spec Kit 1.2.3 and its complete pinned dependency closure as
hash-verified wheels in the existing single pip installation. Its previous PyYAML-only setup could not
satisfy the workspace suite's runtime probe. An initial separate source install violated the existing
wheel-only/hash-lock policy; the focused policy suite now passes 6/6 without weakening that rule.
Strict Python 3.11 wheel-only pip download validated all 41 requirements, and all 377 files in the
published Spec Kit wheel match the previously validated runtime from the pinned source revision.
This prerequisite wiring is not per-skill release/versioning implementation.

The final focused run passed 10/10: those eight new cases plus neighboring root preview and optional
apply. An initial runner-fixture assertion referenced an unavailable diagnostic property; correcting
that fixture yielded all ten passes. The full 366-case result above predates these repairs; do not
claim a complete 374-case rerun until current-head CI or a separately recorded full run supplies it.
Remote PR checks are distinct from these local results. No public artifacts or component tags were
created as part of this close-off.

### Current Consumer Editor Gate

The successfully installed consumer is retained outside the source checkout and opened in a separate
editor window. Its two native commands are:

```text
/speckit-patterns-ports-and-adapters-load
Audit the bundled document-lookup example using its boundary reference and required C# instructions.
Do not edit files or run scripts. List the full installed resource paths you actually read.
```

```text
/speckit-patterns-monolith-modular-load
Review the bundled module/role composition example using its required instructions and references.
Do not edit files or run scripts. List the full installed resource paths you actually read.
```

Select the discovered slash command, not a manually attached loader. Expected canonical reads stay
beneath the corresponding `.specify/extensions/<id>/resources/library/`, with no source/profile
fallback. The loader itself may arrive as an automatic attachment. Current consumer discovery,
invocation and installed-only reads remain pending owner observation; the completed feature 003
editor evidence is historical and does not close this new peer gate. Runtime registration and static
installed-byte verification already pass independently.

| Criterion | Required Demonstration |
| --- | --- |
| SC-001 | Approved apply installs only the exact previewed identities/bytes |
| SC-002 | Preview is unchanged; apply preserves unrelated consumer/profile/source state |
| SC-003 | One of two optional offers selected separately; declined artifact unopened; root unchanged |
| SC-004 | Occupied/local-edit/stale/corrupt cases refuse while preserving caller content |
| SC-005 | Fault/cancel/termination cases retain accurate subsets and block ambiguous retries |
| SC-006 | Real pinned-runtime verification plus separately observed editor discovery/invocation/reads |

Neither the read-only MVP nor synthetic root apply closes SC-001 through SC-006 as end-to-end gates. Later reports must state
unperformed checks and retained partial state rather than treating this guide as full acceptance.
