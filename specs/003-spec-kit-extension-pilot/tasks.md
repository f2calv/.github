# Tasks: Spec Kit Extension Pilot

**Input**: [Specification](./spec.md), [plan](./plan.md), [research](./research.md),
[data model](./data-model.md), [contract](./contracts/extension-pilot.md) and [verification](./quickstart.md).

**Status**: All 12 tasks complete for the bounded local pilot, including owner-confirmed consumer
command discovery/resource loading and final requirements/constitution reconciliation. Approvals cover
the focused tests and isolated local pilot, not public delivery.

## Phase 1: Setup

- [X] T001 Inspect pinned Spec Kit manifest/catalog/command interfaces and record approvals and runtime boundaries in specs/003-spec-kit-extension-pilot/research.md and specs/003-spec-kit-extension-pilot/quickstart.md.
- [X] T002 Capture the bounded feature, constitution checks and public adapter/data interfaces in specs/003-spec-kit-extension-pilot/spec.md, specs/003-spec-kit-extension-pilot/plan.md, specs/003-spec-kit-extension-pilot/data-model.md and specs/003-spec-kit-extension-pilot/contracts/extension-pilot.md.

## Phase 2: Foundation

- [X] T003 Author adjacent synthetic refusal/resource tests before implementation in .github/skills/skill-library/scripts/tests/Invoke-Extension.Tests.ps1; run the explicitly approved expected-failure baseline through the root npm runner and record the result in specs/003-spec-kit-extension-pilot/quickstart.md.
- [X] T004 Implement the inert Linux-only verified-source adapter and exclusive output boundary in .github/skills/skill-library/scripts/Invoke-Extension.ps1, preserving required-only membership without another resolver.

## Phase 3: Generate A Real Extension (US1)

**Independent test**: Generate one accepted manifest with exact native resource bytes and no optional-only payload.

- [X] T005 [US1] Generate the Spec Kit manifest, thin read-only installed-resource command, preserved source/build evidence and required payload in .github/skills/skill-library/scripts/Invoke-Extension.ps1; verify through adjacent synthetic tests and the real build recorded in specs/003-spec-kit-extension-pilot/quickstart.md.

## Phase 4: Discover And Install (US2)

**Independent test**: Search the one-entry local catalog, install the exact version and compare all installed payload hashes.

- [X] T006 [US2] Generate a one-entry digest/version catalog with .github/skills/skill-library/scripts/Invoke-Extension.ps1, then exercise the real pinned CLI in the approved isolated consumer and record exact artifact/runtime identity in specs/003-spec-kit-extension-pilot/quickstart.md.
- [X] T007 [US2] Verify occupied-target and synthetic corrupt-digest refusal using the real local CLI; record unchanged existing payload, nonzero exits and absent rejected payload in specs/003-spec-kit-extension-pilot/quickstart.md without force or broader recovery claims.

## Phase 5: Observe Resource Loading (US3)

**Independent test**: Invoke the generated command in the consumer editor and observe installed root/reference/example/instruction reads.

- [X] T008 [US3] Inspect the generated Copilot command and manually read installed root/reference/example/external-instruction resources; record the distinction between these checks and actual editor invocation in specs/003-spec-kit-extension-pilot/quickstart.md.
- [X] T009 [US3] Open the approved consumer in the intended editor session, verify discovery and invoke /speckit-patterns-ports-and-adapters-load with the representative request in specs/003-spec-kit-extension-pilot/quickstart.md; record observed installed resource reads with no source-checkout fallback before accepting SC-003.

## Phase 6: Close-Out

- [X] T010 Integrate the focused suite in .github/skills/skill-library/scripts/Invoke-Tests.ps1, update .github/skills/skill-library/SKILL.md with the actual pilot boundary and durable fixture/binary/parameter lessons, and record the approved 12-test result in specs/003-spec-kit-extension-pilot/quickstart.md.
- [X] T011 Run configured scoped lint, syntax/editor and local-document-link checks for the new source/tests/design/authority files, recording actual results and reviewing formatter edits in specs/003-spec-kit-extension-pilot/quickstart.md; preserve existing source contracts, versions and unrelated changes.
- [X] T012 After observed editor invocation, reconcile every FR/SC and the constitution against specs/003-spec-kit-extension-pilot/quickstart.md and close only proven obligations in specs/003-spec-kit-extension-pilot/tasks.md. Do not equate manual file reads with native invocation or auto-commit/push/publish.

## Dependencies And Strategy

Setup precedes foundation; US1 enables US2, and both enable US3. T010/T011 can finish before the
editor gate, but T012 depends on T009. No second HVE tracking plan, additional checkout or installer
framework is needed. None of these tasks grants new execution or delivery permissions.

No production-file parallelism is useful: the adapter and its adjacent tests are the shared controlling
surface. Distinct documentation edits may overlap after that surface stabilizes. US1 is the smallest
artifact milestone; US2 establishes the real catalog route; US3 is required for end-to-end acceptance.

## Traceability

| Requirement | Tasks |
| --- | --- |
| FR-001-FR-004; SC-001 | T001-T005 |
| FR-005-FR-007; SC-002 | T005-T007 |
| FR-008; SC-003 | T008-T009 |
| FR-009-FR-012; SC-004 | T001, T004, T007, T010-T012 |
| SC-005 | T008-T012 |

Twelve completed tasks: setup 2, foundation 2, US1 1, US2 2, US3 2, close-out 3. Completion of this
bounded pilot does not authorize or implement the broader optional-aware installer or release system.
