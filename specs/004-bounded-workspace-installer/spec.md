# Feature Specification: Bounded Workspace Installer

**Feature Branch**: `f2calv/2026-10-updates5`

**Created**: 2026-10-28

**Status**: Implemented and real root/optional installation verified on 2026-10-29 under owner authorization;
final regression and current-consumer editor acceptance are recorded separately in the validation guide.

**Input**: User direction: Continue after the verified local extension pilot with a bounded,
workspace-local dependency-aware installer. Preview exact selections before mutation; offer optional
skills as separate explicitly selected extensions; define ownership, conflicts and interrupted-install
behavior before implementation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Review A Complete Installation Preview (Priority: P1)

A maintainer selects one root skill and an existing consumer workspace, then reviews the exact
extensions, versions, required resources, provenance, affected paths and conflicts before approving
any installation.

**Why this priority**: A useful read-only preview establishes the scope of consent and catches missing
artifacts or incompatible consumer state before anything changes.

**Independent Test**: Preview a synthetic root with required and optional dependencies against a
prepared consumer. Compare the selections and conflict report to the authoritative inputs and prove
that consumer files, installation records and profile configuration remain unchanged.

**Acceptance Scenarios**:

1. **Given** a valid root and approved catalog, **When** preview runs, **Then** it identifies exact
   versions and artifact integrity evidence, explains required inclusion, and leaves optional-only
   extensions unselected.
2. **Given** missing artifacts, incompatible versions or occupied targets, **When** preview runs,
   **Then** it reports each blocking condition and does not present an executable installation plan.
3. **Given** an approved preview whose inputs or consumer state subsequently change, **When** apply
   is requested, **Then** the old approval is refused and a fresh preview and approval are required.

### User Story 2 - Install The Approved Root In One Workspace (Priority: P2)

A maintainer approves a ready preview and installs the selected root through the existing extension
runtime without copying guidance into a profile or maintaining a replacement extension installer.

**Why this priority**: This turns the previous single-extension pilot into a repeatable, bounded
consumer workflow while preserving the runtime's ownership of extension registration.

**Independent Test**: Apply an approved root-only plan in a disposable consumer, verify the recorded
version and every installed canonical resource, and compare unrelated workspace and profile files
before and after.

**Acceptance Scenarios**:

1. **Given** an unchanged ready preview and explicit approval, **When** installation completes,
   **Then** the exact root extension is installed with its complete required-only payload and notices,
   its command is registered, and no optional-only extension is downloaded or installed.
2. **Given** corrupted bytes or inconsistent artifact identity, **When** installation is attempted,
   **Then** those bytes are not activated and the operation does not report overall success.
3. **Given** a completed installation, **When** evidence is inspected, **Then** the installed version,
   artifact identity, actual affected paths and verification result are accounted for separately from
   authored library metadata.

### User Story 3 - Choose Optional Extensions Separately (Priority: P3)

A maintainer sees related optional skills and their declared reasons, chooses only the useful ones,
and reviews a new combined preview before installing them as separate extensions.

**Why this priority**: Optional guidance is useful only when consent is explicit and the root's
required-only artifact remains unchanged.

**Independent Test**: Accept one optional extension and decline another. Verify the selected extension
and its own required resources, and prove that the declined extension was neither downloaded nor
installed and that the root artifact remained byte-identical.

**Acceptance Scenarios**:

1. **Given** two declared optional choices, **When** one is selected, **Then** the revised preview
   shows that choice's exact version, additional resources, affected paths and any conflicts.
2. **Given** a revised approved preview, **When** apply completes, **Then** each selected optional
   skill is a separate extension with its own required-only payload, not extra root-archive content.
3. **Given** an optional skill whose required closure overlaps the root's, **When** selections are
   evaluated, **Then** the preview explains that overlap without omitting independently required
   resources, inferring shared-file ownership or activating further optional choices.

### User Story 4 - Preserve Local Work And Diagnose Partial Installation (Priority: P2)

A maintainer encounters an existing extension, local edits, a missing, unreadable or corrupt local
artifact, or an interrupted installation and receives a precise account of what changed and what must
be inspected before retry.

**Why this priority**: A multi-extension operation must not turn a partial result into silent
replacement, ambiguous ownership or an unsafe automatic retry.

**Independent Test**: Exercise occupied targets, conflicting commands, changed installed resources and
interruptions before and after individual extension completion. Verify preserved caller data, accurate
per-extension results and refusal to continue from ambiguous state.

**Acceptance Scenarios**:

1. **Given** an occupied target or conflicting command, including an already installed exact version,
   **When** apply is requested, **Then** it refuses without overwriting, adopting or upgrading it.
2. **Given** one completed extension and a failure on the next, **When** the operation stops,
   **Then** it reports the completed subset, failed or unknown steps and retained recovery locations;
   it does not claim whole-operation success or automatically remove completed extensions.
3. **Given** interrupted or inconsistent installation evidence, **When** another installation is
   requested, **Then** it blocks until the maintainer has reconciled the consumer state and reviewed
   a fresh preview. No automatic resume, force replacement or recursive cleanup is implied.

### Edge Cases

- A declared exact version is absent from the approved catalog, or its artifact evidence disagrees.
- Required cycles, invalid metadata or optional selection keys prevent a complete selection.
- A new optional selection introduces a conflict or another optional choice that was not approved.
- Different extensions contain identical source resources under their separate extension-owned paths.
- An existing extension has the same version but different bytes, or registration exists without files.
- A caller changes catalog contents, selected versions, target files or registration after approval.
- An installation path or ancestor is linked, ambiguous or outside the approved workspace boundary.
- Cancellation occurs during local artifact reading/verification, registration or after one
  extension's successful completion.
- The runtime leaves partial state without returning enough evidence to classify the outcome.
- The installed command is registered but the editor has not refreshed discovery or loaded resources.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Accept one explicit root and one explicit existing consumer workspace. This increment
  MUST NOT install guidance into a user profile or global installation scope.
- **FR-002**: Derive dependencies, exact component versions, optional choice keys and reasons from
  the existing authoritative metadata and graph. Do not infer dependencies from ordinary hyperlinks
  or maintain a competing authored catalog of relationships.
- **FR-003**: Reuse the established required-only artifact boundary. A root extension contains its
  required closure; an optional-only skill is a separate extension only after explicit selection.
- **FR-004**: Produce a preview identifying every selected extension, exact version, artifact location
  and integrity evidence, inclusion reason, required-resource overlap, intended affected paths and
  readiness blockers. Preview MUST NOT mutate consumer installation state or profile configuration.
- **FR-005**: Offer optional choices unselected by default with their declared reasons. Declining a
  choice MUST NOT download its extension artifact, install its payload or activate its optional edges.
  A changed selection requires a new complete preview, not incremental unreviewed installation.
- **FR-006**: Require explicit approval of the concrete ready preview before apply. Bind that approval
  to its selections, exact artifact evidence, destination and inspected consumer state; revalidate
  those inputs before mutation and refuse stale approval rather than selecting substitutes.
- **FR-007**: Use the existing supported Spec Kit extension installation and registration behavior,
  rather than replacing its installer or treating a generated receipt as a second extension registry.
- **FR-008**: Verify selected artifact identity, exact version and integrity before activation and
  account for installed canonical resources and notices afterward. Integrity is not publisher
  authentication, redistribution clearance or acceptance of untrusted catalogs.
- **FR-009**: Confine consumer installation and registration changes to the approved workspace.
  Refuse linked or ambiguous managed paths, existing extension targets, conflicting commands and
  unknown ownership. Do not force replacement, adopt existing files or infer shared ownership from
  equal bytes. Runtime scratch or cache writes outside the workspace require separately approved scope.
- **FR-010**: Preserve canonical library sources, authored versions and dependency pins, unrelated
  consumer files, existing extensions and profile configuration. Native consumption remains available.
- **FR-011**: Maintain generated operation evidence distinct from authored metadata and runtime
  registration. Record the approved selection and artifact provenance, affected paths, observed
  per-extension completion and verification, and incomplete or unknown outcomes without secrets.
- **FR-012**: Stop on the first failure or cancellation, report the completed subset and retained
  recovery locations, and suppress whole-operation success. Preserve local edits and ambiguous state;
  promise neither atomic multi-extension installation nor automatic rollback.
- **FR-013**: Refuse further apply while incomplete or inconsistent operation state remains. Require
  deliberate maintainer reconciliation and a new preview before retry; automatic repair, resume,
  uninstall and destructive cleanup are outside this increment.
- **FR-014**: Require the existing supported runtime and trusted approved catalog/artifact inputs;
  missing prerequisites or unsupported consumer integration fail without provisioning tools, changing
  authentication, configuring new package sources or choosing an unapproved download location.
- **FR-015**: Verify installation and registered command discovery separately from actual editor
  invocation and installed-resource reading. Static registration alone MUST NOT close runtime gates.
- **FR-016**: Keep profile installs, upgrades, uninstallation, concurrent writers, remote publication,
  signing, component releases and cross-platform expansion outside this bounded first increment.
  Tests, real builds and consumer mutation require the approvals owned by the shared authorities.

### Key Entities

- **Selection**: One root and explicitly chosen optional extensions, with exact versions and reasons.
- **Installation preview**: The complete proposed selection, artifact evidence, affected consumer
  paths, observed state, readiness blockers and the approval that must match it.
- **Consumer installation**: Workspace-scoped extension resources and commands owned by the existing
  runtime, distinct from canonical library content and generated artifact evidence.
- **Operation evidence**: Generated provenance, observed changes, verified completions and unresolved
  outcomes needed for deliberate inspection and recovery; not an independent installation registry.
- **Conflict**: Existing or changed content, registration, ownership or artifact evidence that blocks
  a safe application of the approved preview.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every extension installed in the approved scenario matches its previewed identity,
  exact version and artifact evidence; there are zero unpreviewed installations or substitutions.
- **SC-002**: Preview changes zero consumer installation or profile files; applying the approved
  selection changes zero unrelated consumer files, profile guidance or canonical library sources.
- **SC-003**: With at least two offered optional choices and only one accepted, the accepted choice
  is installed separately, the declined artifact is never downloaded, and the root artifact is unchanged.
- **SC-004**: Every occupied-target, local-edit, stale-approval and corrupt-artifact scenario refuses
  unsafe application while preserving existing caller-owned content and reporting the blocking reason.
- **SC-005**: Every tested failure or interruption distinguishes completed, failed and unknown work,
  never reports total success and refuses an ambiguous retry until deliberate reconciliation.
- **SC-006**: One approved disposable-consumer demonstration verifies exact installed resources,
  command registration and a separate observed editor invocation reading installed guidance without
  source-checkout fallback; any unavailable gate is reported as unverified, not passed.

## Assumptions

- This continues the completed local extension pilot with an already initialized compatible consumer
  and the pinned Spec Kit 1.2.3 Copilot skills-mode integration on Linux. Other integrations and native
  Windows acceptance are not inferred from that pilot.
- Approved local catalogs and trusted generated extension artifacts are sufficient for first
  acceptance. Public releases, broad catalog federation and rights-clearance decisions are separate.
- The maintainer controls a stable workspace and approves one operation at a time. This is not a
  filesystem sandbox against hostile same-user or privileged concurrent mutation.
- Existing installations are blockers, even at the requested version; upgrades, adoption and
  idempotent reapplication are deliberately deferred to keep first-install ownership unambiguous.
- Recovery initially means preserving evidence and providing an actionable account for deliberate
  reconciliation, not introducing an automatic repair or rollback engine.
- This specification does not authorize implementation, tests, real artifact builds, catalog hosting,
  consumer installation, commits, pushes or acceptance of remaining distribution ADR proposals.
