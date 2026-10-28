# Validation Guide: Spec Kit Extension Pilot

**Status**: Complete for the bounded local pilot. Real generation, catalog discovery, exact-version
installation and negative CLI checks passed. The owner confirmed native consumer command invocation
and installed-only resource reads. Final requirements/constitution reconciliation is recorded below.

## Approval And Runtime

On 2026-10-28 the owner explicitly approved focused Pester tests, local builds, loopback-only hosting
and an isolated retained consumer sandbox. This was not permission for public hosting, publication,
tool installation, commits, pushes or the broader dependency-aware installer.

Observed runtimes are Linux, PowerShell 7.6.9, Spec Kit 1.2.3 and Pester 5.7.1. The source archive
used the existing installed CPython 3.13.5/PyYAML 6.0.3 interpreter and Git 2.56.0. No tools installed.

## Focused Checks

The approved missing-adapter baseline failed as expected; it was not a passing gate. Two local defects
then produced 9 passes/1 failure: dot-sourcing reset the caller destination, and JSON binary output
was enumerated into an object array rejected by the stream. Explicit parameter forwarding and a
single-byte-array return fixed them. The suite passed 10 tests, then 12 after adding CLI JSON and
linked-ancestor refusal cases: 12 passed, zero failed/skipped, through the configured npm runner.

Coverage includes inert loading, exact required resource bytes, generated catalog/version/digest,
wrong artifact digest, unsafe source evidence, optional selection, unexpected members, existing output,
linked output ancestry and non-loopback HTTP refusal. The root runner's unrelated container coverage
table is not extension coverage. No unchanged broad repository regression is claimed.

### Pre-PR Review Correction

The owner approved a focused correction and test run after local review found that the loader
selected instructions only by the `.instructions.md` suffix. A declared `docs/policy.md` fixture
reproduced the omission: 12 tests passed and the new case failed. Selecting manifest
`external-instruction` reasons as well as conventional filenames then passed all 13 adapter tests,
with zero failures/skips through the same configured npm runner. The retained real pilot below was
not rebuilt or reinstalled after this correction; its original digests and editor evidence remain
specific to that recorded build.

## Static Validation

All six applicable configured hooks passed after the EOF fixer normalized final newlines. The three
touched PowerShell files parsed without errors; source/test/runner editor diagnostics were clear.
All 19 local documentation links resolved. Saved-file validation caught a retained plan-template
prefix; removing it cleared the scaffold check. Feature 002's saved task ledger matches Git HEAD.
No Spec Kit extension-hook configuration is present in the source checkout.

Editor diagnostics still reported cached Markdown EOF warnings after the saved files had one final
newline and configured Markdown lint passed. Editor diagnostic refresh was not verified; these
warnings are not treated as source failures or evidence of consumer command discovery.

## Real Local Pilot

Root `patterns-ports-and-adapters`, version `1.0.0`, source commit
`b3999dc62b983bd5f82a2dfbf75a854d9aeca92c`:

- Source archive SHA-256: `83a125e02afeff0e3d7e9ebf1d79ea15db53a63dc0f60992512a5ae183799c76`.
- Extension ZIP SHA-256: `be24c1246fe2351a6f86ba09a3cc3dfd0ab630012b49e3bceb77bef066bad713`.
- One catalog entry was found through real `specify extension search`.
- Real `specify extension add patterns-ports-and-adapters --version 1.0.0` accepted the manifest,
  verified/downloaded the archive and registered one Copilot skill command.
- All six installed canonical source files matched the embedded source manifest's SHA-256 values.
- Reinstalling without force returned exit 1; installed payload hashes remained unchanged.
- A separate consumer's synthetic wrong catalog digest returned exit 1 and created no installed payload.
- Final missing-source CLI check returned exit 1 with an `Input:` diagnostic, no success output and
  no output directory created. Both archive digests and all six installed source hashes were rechecked
  against the evidence above and remained unchanged; optional selections remained empty.
- An initially incomplete consumer fixture emitted an event-refresh warning because its Copilot
  integration manifest was absent. After copying the existing pinned manifest, a real disable/enable
  cycle completed without that warning. This is a minimal consumer fixture, not a full bootstrap claim.

The isolated workspace, native archive and generated site are retained at the owner-approved local
location reported in the session. They are not tracked library content. Loopback hosting is temporary;
installed-resource invocation needs no server. Catalog cache and registry files belong to Spec Kit.

## Reproduce In An Approved Consumer

Use the [adapter contract](./contracts/extension-pilot.md), obtain the existing build's expected digest
and choose new output. Substitute approved local paths and an available loopback port:

```powershell
./.github/skills/skill-library/scripts/Invoke-Extension.ps1 `
   -ArchivePath /path/to/native/package.zip -ArchiveSha256 <expected-sha256> `
   -OutputDirectory /path/to/new-site -BaseUri http://localhost:8123/
```

Host only that generated site on loopback using existing tools. In the approved consumer, use its
pinned Copilot integration/init settings and integration manifest, then run:

```text
specify extension catalog add http://localhost:8123/catalog.json --name local-pilot --install-allowed
specify extension search patterns-ports-and-adapters
specify extension add patterns-ports-and-adapters --version 1.0.0
```

Do not enable install trust for an unvetted catalog. Do not use force, perform upgrades, provision
packages or copy the generated extension into canonical sources. Existing target refusal is not
proof of a general local-edit, shared-ownership, interrupted-install or rollback contract.

## Editor Acceptance

Open the retained consumer folder in the same container, preferably in a separate editor window.
Start a new Copilot chat or refresh customization discovery as necessary. Confirm this exact command
is offered and invoke it:

```text
/speckit-patterns-ports-and-adapters-load
Audit the bundled document-lookup example using its boundary-contract reference and C# instructions.
Do not edit files. List the installed resource paths you actually read.
```

The generated skill resides at `.github/skills/speckit-patterns-ports-and-adapters-load/SKILL.md`.
Its source is `extension:patterns-ports-and-adapters`. Required reads are beneath
`.specify/extensions/patterns-ports-and-adapters/resources/library/`:

- `.github/skills/patterns-ports-and-adapters/SKILL.md`.
- `.github/skills/patterns-ports-and-adapters/references/boundary-contracts.md`.
- `.github/skills/patterns-ports-and-adapters/examples/provider-substitution.md`.
- `.github/instructions/dotnet.csharp.instructions.md`.

Initial manual reads verified access and relative placement, not native consumer command invocation.
On 2026-10-28, after opening the isolated consumer in a separate same-container VS Code window and
receiving the invocation request above, the owner supplied the resulting audit. It listed the expected
root, C# instruction, boundary reference and provider-substitution example as installed resources read,
with no other optional resources read and no edits, tests or scripts executed.

The initial pasted resource list contained basenames rather than full paths. In a follow-up, the
consumer chat explicitly confirmed that all four resource reads were inside the installed extension's
`resources/library/`, with no guidance read outside it and no additional file reads. This is
owner-supplied runtime evidence of installed-only resource loading, not an independently inspected
read trace. No further resource reads are needed for that confirmation.

The follow-up also said the loader instructions arrived as an attachment rather than through a tool
read. That can be normal when Copilot supplies a selected skill's instructions; a separate loader
file read is not required. The attachment alone does not distinguish editor-discovered command
selection from manually attaching a file. The owner explicitly confirmed using
`/speckit-patterns-ports-and-adapters-load`, with Copilot attaching the loader automatically, not a
manual file attachment. Together with the installed-only reads, this closes SC-003 and T009 on
owner-reported editor runtime evidence. The final reconciliation below closes T012.

The audit found undefined lookup bounds, freshness guarantees, and failure/cancellation assertions
in the illustrative example. These are canonical-guidance review items, not evidence that extension
packaging failed or provider implementations were tested. They remain deferred because this pilot
verifies delivery/loading of the committed guidance, not revision or provider conformance of that
example. Any follow-up belongs to the ports-and-adapters skill; changing it requires a separately
reviewed source change and a new archive before claiming the changed guidance was installed.

## Final Acceptance

On 2026-10-28, the current adapter, adjacent tests, plan and constitution were reconciled against
every functional requirement and success criterion. No remaining obligation was identified within
this local pilot's scope. Historical passing checks are not presented as newly rerun tests.

| Requirement | Evidence and bounded outcome |
| --- | --- |
| FR-001, FR-002 | Adapter consumes the trusted required-only archive, derives root identity/version, preserves source evidence and generates only extension-specific wrappers/indexes. No second resolver or authored guidance copy. |
| FR-003, SC-001 | Accepted extension contains all six required source files/notices at preserved relative paths; installed hashes match and optional selections are empty. |
| FR-004 | Pinned runtime accepts the namespaced read-only command; its generated body forbids edits, packaged scripts, optional downloads and source/profile fallback. No core override or automatic install hook. |
| FR-005, FR-006, FR-007, SC-002 | One-entry real catalog search and exact-version install passed; recorded artifact hashes, six installed hashes and notice bytes match. Integrity is not authentication or rights clearance. |
| FR-008, SC-003 | Owner confirmed the discovered slash command automatically supplied its loader, and the consumer reported root, reference, example and external instruction reads only inside installed resources. This is owner-reported runtime evidence, not an independently captured editor trace. |
| FR-009, SC-004 | Explicit local test/build/loopback/consumer approvals recorded; missing/corrupt input and occupied-target refusals observed without force or tool installation. |
| FR-010 | Actual runtime/artifact identity, installed and generated command paths, incomplete-fixture warning/fix and retained-partial-output/interruption limits recorded above and in the contract. |
| FR-011, FR-012 | Optional downloads, general installation/recovery, publication and releases remain excluded. Generated artifacts/consumer state stay outside canonical sources; no authored version/pin changes. |
| SC-005 | Generation, catalog discovery, installation and owner-reported editor/resource loading each have separate evidence; static registration/manual reads did not close the editor gate. |

Constitution review: I preserves canonical ownership; II has native discovery and progressive-loading
evidence; III distinguishes inspected/static, executable and owner-reported results and records the
illustrative example's limitations; IV keeps metadata, generated artifacts and consumer state separate;
V retains the recorded execution approvals without new commit/push/publication authority. No exception
or governance amendment is needed. The broader distribution ADR is not accepted or completed by this
pilot, and the unverified limits below remain unchanged.

## Limits And Feedback

The adapter's trusted-source and stable-parent bounds are narrower than a general importer/installer.
Extension-format cross-runtime reproducibility, native Windows, optional downloads, upgrades,
interrupted installs, consumer-edit recovery, rights clearance, signatures and publication are unverified.

Customization feedback is folded into the owning skill: pinned Spec Kit contracts and complete
integration fixtures, single binary-array returns and explicit dot-source destination forwarding.
