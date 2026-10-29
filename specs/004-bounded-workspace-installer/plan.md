# Implementation Plan: Bounded Workspace Installer

**Branch**: `f2calv/2026-10-updates5` | **Date**: 2026-10-28 | **Spec**: [Specification](./spec.md)

**Input**: `specs/004-bounded-workspace-installer/spec.md`

**Status**: Implementation and real root/optional installation verified on 2026-10-29 under owner
authorization. The validation guide records actual evidence, remaining regression/editor gates and
retained failure consumers; design completion alone is not acceptance.

## Summary

Extend the existing skill-library tool bundle with a first-install-only workspace orchestrator.
Reuse committed inventory/validation for one root and explicit optional choices; verify existing local
catalogs and prebuilt extensions, preview the complete operation, then require a matching approval.
Install each selected extension separately through the pinned upstream installer, preserving its own
required-only payload. Stop on failure, retain evidence and require manual reconciliation before retry.

Use a thin Python adapter to Spec Kit 1.2.3's current `install_from_archive` API with a verified open ZIP
stream because that release has no local-ZIP CLI flag. This is a version-pinned integration, not a new
extractor or dependency resolver.
Public/profile installation, remote acquisition, upgrades, adoption and automatic rollback are excluded.

Resolved choices and inspected-source evidence are in [research](./research.md). The
[data model](./data-model.md), [command contract](./contracts/workspace-install.md) and
[validation guide](./quickstart.md) define generated evidence, approval/apply behavior and later gates.

## Technical Context

**Language/Version**: PowerShell 7.4+ orchestration; existing CPython 3.11+ with PyYAML 6.0.3;
the apply interpreter must also contain the inspected Spec Kit CLI 1.2.3 distribution.

**Primary Dependencies**: Existing committed inventory/validation helpers, schemas and Git process
boundary; Python standard library and pinned upstream extension manager. No new package is planned.

**Storage**: Read-only committed source and approved local catalog/artifact files. Runtime-owned
workspace registration stays authoritative. Separate generated operation evidence records approval,
observed changes and recovery state; no authored relationship index or replacement registry.

**Testing**: Adjacent Pester 5.7.1 synthetic suite through the configured npm runner, after separate
approval. Real pinned-runtime and editor gates require an explicitly approved disposable consumer.

**Target Platform**: Linux; already initialized built-in Copilot skills-mode consumer. Reject external
adapters, incompatible runtime/configuration and unsupported output side effects rather than widening scope.

**Project Type**: Extension of the existing skill-owned administrative tool bundle, not a new project.

**Performance Goals**: No latency claim. Hash only selected artifact/resource bytes, never materialize
declined artifacts, and bound archive inspection using the preceding adapter's 64 MiB archive/payload
and 16 MiB member limits. Limit one operation to 16 selected extension roots.

**Constraints**: Preview is consumer-read-only. Apply recomputes fingerprinted inputs, refuses existing
targets and conflicting commands, delegates installation, verifies results, and retains ambiguous state.
No package setup, automatic hooks, profile writes, force replacement, arbitrary source remaps or hidden
network fallback. Declare and confine temporary extraction; do not claim a hostile-writer sandbox.

**Scale/Scope**: One source commit, one root, explicitly selected optional roots, one consumer and one
operation at a time. Shared resources remain separately owned beneath each extension's resource tree.

## Constitution Check

Initial and post-design review found no proposed exception. Implementation and runtime acceptance
remain separate gates; a design pass is not approval to execute those later phases.

| Principle | Design Obligation | Initial Gate | Post-Design Gate |
| --- | --- | --- | --- |
| I: Canonical ownership | Existing skill owns tooling; upstream owns install/registration; native use unchanged | Pass | Pass |
| II: Scoped discovery | Built-in Copilot only; command registration and observed installed reads are separate | Pass | Pass |
| III: Evidence | Research labels source inspection; contracts constrain effects; runtime acceptance remains unverified | Pass | Pass |
| IV: Metadata separation | Existing graph owns selection; per-root payloads and operation receipts are generated | Pass | Pass |
| V: Approval | Planning authorizes no tests/builds/consumer use/delivery; guide retains independent approvals | Pass | Pass |

## Project Structure

### Documentation (this feature)

```text
specs/004-bounded-workspace-installer/
  spec.md
  checklists/requirements.md
  plan.md
  research.md
  data-model.md
  contracts/workspace-install.md
  quickstart.md
```

Task generation is the next stage; this command does not create `tasks.md`.

### Source Code (repository root)

Planned changes, not files created by this planning command:

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

**Structure Decision**: Keep orchestration and the narrow upstream adapter with their existing owner.
Add a detached committed-selection projection beside inventory internals without changing the existing
public preview result. Reuse the same fixtures, Git helpers and npm test entry point; no new framework,
general installer service or authored metadata schema is justified.

## Requirement Coverage

| Requirements | Design Anchor | Planned Observable Check |
| --- | --- | --- |
| FR-001, FR-009, FR-010 | Contract: PowerShell Surface, Accepted Runtime Profile, Approved Mutation Set | One workspace; preserve source/profile/unrelated bytes and modes; reject links/conflicts |
| FR-002, FR-003, FR-005 | Model: Selection, Local Artifact | Existing validator; separate required-only roots; offers default off; declined ZIP unopened |
| FR-004, FR-006 | Model: Preview And Conflicts; contract: Preview Result And Approval | Read-only complete preview; changed input/state invalidates approval |
| FR-007, FR-008 | Research: upstream decision; contract: Upstream Bridge | Same verified stream; existing runtime registration; exact installed resources/notices |
| FR-011, FR-012, FR-013 | Model: Operation Evidence, State Transitions; contract: Apply Outcomes And Recovery | Durable intent, verified/failed/unknown subsets, stop/preserve/block retry |
| FR-014, FR-016 | Contract: Accepted Runtime Profile and local-only parameters | Missing/unsupported prerequisites fail without setup, network or wider scope |
| FR-015 | Guide: Editor Runtime Gate | Separate file/registration evidence from actual discovered invocation and installed reads |
| SC-001 through SC-006 | Guide: Acceptance Record | Approved synthetic cases and separate disposable-runtime/editor demonstration |

## Risks And Validation Boundaries

- The internal upstream API is deliberately version-pinned. Signature/module drift blocks rather
  than falling back to a custom installer; the inspected package source is not runtime acceptance.
- Upstream registration may skip files, normalize configuration or chmod scripts. Predict effects
  and reject consumers/payloads that cannot preserve unrelated state, including comments and modes.
- Process-local temporary-directory settings require an observed later runtime check. The trusted
  stable-workspace assumption excludes hostile concurrent writers and is not a sandbox claim.
- Multi-extension installation is non-atomic. Retain partial state and durable evidence; no automatic
  resume/rollback/reconciliation is promised, and completed targets continue to block reapplication.
- The current stage generated design artifacts only. Focused tests, real runtime use and editor
  observations remain unrun and require their own approval; no artifact publication is proposed.

## Complexity Tracking

No constitution violations or exceptions require justification. The only new boundary is a small
bridge to the existing pinned installer; metadata resolution and runtime ownership remain unchanged.
