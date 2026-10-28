# Implementation Plan: Deterministic Skill Archives

**Feature**: `002-deterministic-skill-archives` | **Date**: 2026-10-27 | **Spec**: [Specification](./spec.md)

**Working branch at planning**: `f2calv/2026-10-updates4`

**Input**: [Feature specification](./spec.md). The preceding PR is merged and the new working branch
is checked out. The original spec's branch-hold wording records its creation context, not a request
to switch back. Planning leaves all work uncommitted; no runtime implementation is authorized here.

## Summary

Add a local archive operation to the existing skill-library tool bundle. Require one explicit root,
invoke the existing committed inventory with no optional selections, and package only its eligible
files. Keep optional recommendations in authored metadata but never add optional-only payloads.

PowerShell orchestrates trusted inventory and binary Git reads. An isolated trusted Python helper
uses standard-library `zipfile` with stored entries and explicit metadata, embeds canonical build
evidence, and emits a detached SHA-256 checksum. Reserve a new output directory exclusively outside
the repository and Git administration paths; fail without overwriting existing output. This is a
local build contract, not an installer, extension-loader format agreement or release workflow.

## Technical Context

**Language/Version**: PowerShell 7.4+ and CPython 3.11+; record exact runtime versions in build inputs.

**Primary Dependencies**: Existing Git process helper, committed inventory, metadata validator,
bundled schemas and installed PyYAML 6.0.3. New writer uses Python stdlib only. No added packages.

**Storage**: Inert committed Git blobs; private temporary staging outside source/Git directories;
one explicit new output directory containing `package.zip` and `package.zip.sha256`.

**Testing**: Adjacent synthetic Pester 5.7.1 archive suite; reuse existing fixture conventions
and runner. Tests require separate explicit approval. Independent ZIP inspection and header checks
must not use the writer's own expected-output generator as their only oracle.

**Target Platform**: Linux dev container and trusted local filesystem parents. Initially support
only CPython on Linux; reject other operating systems/implementations before output reservation.
Byte-equivalence claims require observed evidence per exact supported runtime tuple. Windows and
cross-runtime equivalence are unverified, not inherited from the preceding feature's waiver.

**Project Type**: Bundled local command and dot-sourceable object API, not a new application/project.

**Performance Goals**: No network or compression work; process payload files sequentially through
the existing byte-safe Git boundary. No latency or peak-memory guarantee is claimed during planning.

**Constraints**: One root; no optional-selection parameter; no source mutation, tool installation,
version changes, tags, installation or publication. Fixed archive contract and no ZIP64. Explicit
output must be new, outside the entire source repository and Git administrative/common directories.

**Scale/Scope**: One package per invocation; at most 65,534 members including evidence; predicted
complete ZIP size at most 1 GiB; member names at most 65,489 UTF-8 bytes. These are conservative
contract limits, not claims about ZIP format maxima or hostile-input memory bounds.

## Constitution Check

Pre-research evaluation and post-design recheck passed. The post-implementation recheck also passes;
the [validation guide](./quickstart.md#final-gates-and-pilot) records approved runtime results and
remaining support limits. No constitution exception is requested.

| Principle | Design evidence | Post-design result |
| --- | --- | --- |
| I: Canonical ownership | Extend the existing skill-library bundle; no copied authored skill source or new catalog. | Pass |
| II: Scoped discovery | No discovery migration or automatic loading; retain native skill directories and relative layout. | Pass |
| III: Evidence-based guidance | Versioned byte contract, output threat model and observed executable checks are explicit; claims stay within the verified tuple. | Pass |
| IV: Separate generated outputs | Reuse inventory membership; derive manifest/digests separately from authored metadata and consumer state. | Pass |
| V: Approval and validation | Implementation, synthetic tests and the real pilot received separate authorization; no commits, pushes, releases or installs by this implementation. | Pass |

Authorities remain the [constitution](../../.specify/memory/constitution.md),
[owning skill](../../.github/skills/skill-library/SKILL.md),
[workflow rules](../../.github/instructions/workflow.instructions.md) and
[GitHub rules](../../.github/instructions/github.instructions.md). Code follows the existing
PowerShell/Python instructions; this plan does not amend them or the still-In-Progress distribution ADR.

## Project Structure

### Documentation (this feature)

```text
specs/002-deterministic-skill-archives/
  spec.md
  checklists/requirements.md
  plan.md
  research.md
  data-model.md
  contracts/archive-build.md
  quickstart.md
```

[Task ledger](./tasks.md) was generated by `/speckit-tasks` after this design and is closed against
the observed implementation, scoped lint, four-suite regression and separately approved real pilot.

### Source Code (repository root)

Implemented surface, created during the separately authorized implementation rather than planning:

```text
.github/skills/skill-library/
  SKILL.md                              # update only after implementation
  scripts/
    Invoke-Archive.ps1                  # new public CLI/object orchestration
    Write-Archive.py                    # new trusted stdlib writer/output helper
    Invoke-InventoryPreview.ps1         # reuse public API, unchanged contract
    Invoke-Validation.ps1               # reuse validation, no second resolver
    Git-Process.ps1                     # reuse byte-safe isolated Git/process calls
    Read-Metadata.py                    # reuse isolated metadata reader
    Invoke-Tests.ps1                    # add archive suite after approval
    tests/Invoke-Archive.Tests.ps1      # new synthetic archive cases
```

**Structure Decision**: Keep this feature in its owning skill bundle. A single Python helper owns
ZIP bytes and Linux output creation; PowerShell owns integration with the existing inventory API.
Do not introduce a second metadata schema, reusable ZIP framework or separate test-support project.

## Phase 0 Decisions

[Research](./research.md) resolves format/metadata normalization, manifest integrity, trusted-tool
identity, immutable source reads, safe destination reservation and platform scope. All initial
technical questions are resolved; no outstanding design clarification blocks Phase 1.

## Phase 1 Design

[Data model](./data-model.md) defines requests, evidence and output lifecycle.
[Archive contract](./contracts/archive-build.md) defines the CLI/object interface, wire fields,
byte format, bounds and failure behavior. [Quickstart](./quickstart.md) defines future approved
validation scenarios, not observed test results.

## Complexity Tracking

No principle violations. Descriptor-relative Linux output operations are justified by the no-link
and no-overwrite contract. Atomic directory publication, hostile-writer isolation and a native
Windows equivalent are deliberately not promised; their absence is explicit in the contract.
