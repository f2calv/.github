# Implementation Plan: Packaging Inventory Preview

**Feature**: `001-packaging-inventory-preview` | **Date**: 2026-10-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-packaging-inventory-preview/spec.md`

**Feature identifier**: `001-packaging-inventory-preview`. Setup returns this as `BRANCH`;
it is not the actual Git branch above. Planning creates no branch or implementation.

## Summary

Add a read-only PowerShell inventory command under skill-library. Resolve one local commit,
read its tree/blobs as inert data, and reuse trusted metadata validation for the complete opted-in
catalog and selected closure. Report eligible selected files once with all ownership, dependency
and declaration reasons. Historical scripts are payload, never executable tooling.

See [research](research.md) and the [command contract](contracts/inventory-preview.md).
Archives, installation, version preparation, release records and publication remain excluded.

## Technical Context

**Language/Version**: PowerShell 7.4+; existing restricted reader uses Python 3.11+.

**Primary Dependencies**: Local Git supporting `rev-parse --end-of-options`, NUL-delimited
`ls-tree`/`check-ignore`, raw `cat-file`; PyYAML 6.0.3; bundled schemas and `Test-Json`.
No new third-party dependencies or automatic provisioning.

**Storage**: Local Git objects and temporary inert files outside the worktree; no persistent
inventory, source clone, registered worktree or database.

**Testing**: Pester 5.7.1 synthetic repositories through the adjacent focused runner. Separate
test approval is required; planning runs no tests or preview implementation.

**Target Platform**: PowerShell on Linux and Windows; native Windows verification remains a
later gate, not a claim established by this design or a Linux pass.

**Project Type**: Maintainer-facing local command bundled in a native skill.

**Performance Goals**: Stable review order without enumerating every graph path; bounded
discovery excludes unrelated unconverted trees. No numerical benchmark is in scope.

**Constraints**: Offline, binary fidelity, snapshot-only ignore policy, no payload execution,
caller Git-state mutation or partial-success inventory; cleanup on success and failure.

**Scale/Scope**: One local commit per invocation. Validate all opted-in records; emit selected
closure only. Current repository has three opted-in components.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Authority: [constitution](../../.specify/memory/constitution.md),
[repository instructions](../../.github/copilot-instructions.md),
[workflow](../../.github/instructions/workflow.instructions.md) and
[skill-library](../../.github/skills/skill-library/SKILL.md).

| Principle | Before Research | After Design |
| --- | --- | --- |
| I. Single ownership | Pass: extend skill-library. | Pass: colocated command/helper/tests, no duplicate library. |
| II. Scoped discovery | Pass: no discovery-path changes. | Pass: update existing skill after implementation. |
| III. Evidence | Pass: inspect APIs and label proposals. | Pass: research evidence and future validation guide. |
| IV. Explicit metadata | Pass: preserve validator authority. | Pass: decorate its membership, do not resolve another graph. |
| V. Approval | Pass: planning only. | Pass: tests and implementation remain separately gated. |

No exception is needed. Leave the temporary constitution review report untouched; removal
before a future commit is outside this planning command.

## Project Structure

### Documentation (this feature)

```text
specs/001-packaging-inventory-preview/
|-- spec.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/inventory-preview.md
`-- checklists/requirements.md
```

### Source Code (repository root)

Planned changes, not files created by this command:

```text
.github/skills/skill-library/
|-- SKILL.md                              # Document implemented command
`-- scripts/
   |-- Invoke-InventoryPreview.ps1       # New command and object function
   |-- Git-Process.ps1                   # Private shared byte-safe process boundary
   |-- Invoke-Validation.ps1             # Reuse; isolate trusted Python launch
   |-- Invoke-VersionPreparation.ps1     # Use shared process boundary only
   |-- Invoke-Tests.ps1                  # Include adjacent inventory suite
   `-- tests/Invoke-InventoryPreview.Tests.ps1
```

**Structure Decision**: Follow the colocated validator/preparation layout. Extract only genuinely
shared byte-safe subprocess/environment behavior; leave release-baseline/working-tree policy in
preparation. Do not copy its working-input inventory or tag restrictions. No new metadata schema.

## Design and Validation Sequence

1. Establish the shared Git process boundary with regression coverage for preparation. Capture
  raw bytes and sanitize errors; disable inherited Git overrides, optional locks and network.
2. Resolve a source commit once; walk immediate sidecars, opted-in trees and exact declarations.
  Retain source mode/path/blob identity. Reject unsafe paths, links and gitlinks before writing
  inert data outside the worktree. No source checkout, filter or hook execution.
3. Use trusted reader/schemas/validator, not historical scripts. Retain raw declarations, call
  `Invoke-SkillValidation -IncludeCatalog`, then decorate its membership with roots/incoming
  edges. Isolate Python with `-I -B`; regression-check existing reader/preparation callers.
4. Evaluate snapshot ancestor `.gitignore` rules using Git in empty auxiliary metadata beside
  inert data. No source objects, refs or checked-out revision. Validate the full opted-in trees
  before filtering payload; ignored mandatory files fail.
5. Assemble complete ordered output, clean up, then emit success. Retain every owner/reason for
  shared paths. Cleanup failure suppresses success and reports the need for operator cleanup.
6. With separate approval, run the focused synthetic suites and [quickstart](quickstart.md).
  Cover dirty checkouts, historical malicious scripts/imports, binary files, nested ignore
  negation, catalog-wide failures, selected optional cycles, diamonds and both cleanup paths.
  Verify native Windows behavior before claiming cross-platform support.

FR-001 through FR-012 map to the [contract](contracts/inventory-preview.md). Entities and state
transitions are in [data-model.md](data-model.md). Executable tasks belong to `/speckit-tasks`.

## Complexity Tracking

No constitution violations. Two temporary contexts serve different purposes: inert source data
and empty Git metadata for native ignore matching. Neither is an alternate source checkout,
package cache or persistent inventory. Their trust boundary and lifecycle are in research.
