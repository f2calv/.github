# Feature Specification: Spec Kit Extension Pilot

**Feature Branch**: `f2calv/2026-10-updates4`

**Created**: 2026-10-28

**Status**: Complete for the bounded local pilot; generation/discovery/installation verified,
consumer command invocation and installed-only resource reads confirmed by the owner.

**Input**: User description: "One genuine Spec Kit extension and a minimal catalog entry, proving
discovery, installation and resource loading before expanding the custom dependency-aware command."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Produce One Usable Extension (Priority: P1)

A maintainer generates a real Spec Kit extension from one committed skill and its required payload,
without maintaining another authored copy of that guidance.

**Why this priority**: A catalog or installation demonstration has no value unless its artifact is
actually accepted by Spec Kit and contains the resources the skill needs.

**Independent Test**: Inspect a generated extension with the pinned installed Spec Kit validator and
compare its canonical resource bytes, identities and notices to the selected committed inventory.

**Acceptance Scenarios**:

1. **Given** one valid committed skill, **When** its extension is generated, **Then** Spec Kit accepts
   its manifest and it contains the root, required closure, external instructions and applicable notices.
2. **Given** a related optional skill, **When** the root extension is generated, **Then** optional-only
   payload is absent and independently required overlap remains included.
3. **Given** missing content, unsafe paths or inconsistent identity/version evidence, **When** generation
   is requested, **Then** it fails without reporting a complete usable extension or altering native sources.

### User Story 2 - Discover And Install Through The Catalog (Priority: P2)

A consumer discovers the pilot in a minimal local catalog and installs its exact version using the
existing Spec Kit extension interface, not a bespoke replacement installer.

**Why this priority**: This establishes whether the proposed catalog route works in the actual runtime.

**Independent Test**: In an explicitly approved consumer workspace, search the local catalog and
install the selected exact version through Spec Kit; inspect its registered extension and commands.

**Acceptance Scenarios**:

1. **Given** a configured one-entry local catalog, **When** a consumer searches, **Then** the expected
   extension identity, version and description are discoverable without public publication.
2. **Given** that entry and an approved clean consumer, **When** its exact version is installed,
   **Then** Spec Kit records that version and registers the declared namespaced Copilot command.
3. **Given** unavailable or corrupted artifact bytes or an occupied installation target, **When** an
   install is attempted, **Then** the observed refusal or conflict behavior is recorded without silently
   forcing replacement, claiming recovery guarantees or modifying unrelated consumer files.

### User Story 3 - Invoke The Command And Read Its Resources (Priority: P3)

A Copilot user invokes the installed extension command and the assistant reads the installed skill
and relevant bundled resources, without relying on the source checkout or loading the whole library.

**Why this priority**: File installation and command registration do not establish editor discovery
or actual resource loading.

**Independent Test**: Invoke the registered command in the intended editor session and record which
installed skill, reference/example and external instruction were actually read for a representative task.

**Acceptance Scenarios**:

1. **Given** an installed extension visible to Copilot, **When** its command is invoked, **Then** it
   reads its installed root guidance and identifies the resources relevant to the requested task.
2. **Given** a task needing a bundled reference/example and external instruction, **When** the command
   runs, **Then** those installed resources are read without using their original checkout paths.
3. **Given** only static file/registration evidence or an unavailable editor invocation, **When** results
   are reported, **Then** actual command discovery and loading remain explicitly unverified.

### Edge Cases

- The catalog identity/version disagrees with the extension manifest or captured source evidence.
- A catalog entry points to missing, modified or unsafe archive content.
- A consumer has an existing extension or conflicting generated command; no force overwrite is implied.
- Resource-relative links resolve in the source checkout but not beneath the installed extension.
- Native instruction activation is incorrectly inferred from copying instructions under an extension.
- The installed CLI works but the attached editor has not refreshed command discovery.
- Local artifact hosting stops or a consumer verification run is interrupted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Generate one real extension from exactly one selected committed native skill, reusing
  the existing metadata, inventory and required-only archive boundaries rather than another resolver.
- **FR-002**: Derive distribution identity/version and native content from authoritative inputs;
  generated wrappers, manifests and catalog entries MUST NOT become independently authored guidance.
- **FR-003**: Include the complete required payload and notices once, preserve resource-relative
  geometry, exclude optional-only payload and leave native consumption unchanged.
- **FR-004**: Provide a namespaced read-only loading command accepted by the pinned Spec Kit/Copilot
  integration, without overriding core commands or adding automatic installation hooks.
- **FR-005**: Generate one minimal catalog entry with the selected exact version, artifact location
  and integrity evidence supported by the actual pinned runtime; do not invent catalog fields.
- **FR-006**: Demonstrate discovery and exact-version installation through the real Spec Kit
  interfaces using approved local artifacts and hosting, without public release or publication.
- **FR-007**: Verify installed content against its expected source/artifact evidence, preserve notice
  attribution, and distinguish byte integrity from publisher authentication or redistribution approval.
- **FR-008**: Verify real Copilot command invocation and installed-resource reading separately from
  CLI registration and static checks; unobserved editor behavior MUST remain an open acceptance gate.
- **FR-009**: Scope consumer mutation to an explicitly approved workspace; require separate approval
  for tests, artifact builds, installation and setup. Do not silently force conflicts or install tools.
- **FR-010**: Record the actual runtime, artifact identity, changed consumer paths, conflicts and
  interruption limitations. Claim no stronger ownership, rollback or concurrency safety than observed.
- **FR-011**: Keep optional-skill downloads, general dependency-aware installation, upgrades,
  uninstall/recovery redesign, catalog fleet automation, tags and publication outside this pilot.
- **FR-012**: Keep generated artifacts and consumer state separate from tracked canonical sources;
  verify the pilot without committing machine-specific locations or editing authored versions/pins.

### Key Entities *(include if feature involves data)*

- **Extension artifact**: Generated manifest, thin loading command, canonical required resources,
  notices and build evidence for one exact root/version/source.
- **Catalog entry**: Generated discovery and exact-version location/integrity record for that artifact.
- **Consumer installation**: Spec Kit-managed local extension and registered command, distinct from
  authored metadata and generated source/build evidence.
- **Verification record**: Observed generation, discovery, installation and resource-loading outcomes,
  with approvals, runtime identities and unverified boundaries recorded separately.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One generated extension is accepted by the target runtime, with every expected required
  source file and notice accounted for and zero optional-only payload files.
- **SC-002**: A consumer discovers the single catalog entry and installs its recorded exact version;
  installed source bytes and artifact integrity match the recorded expected evidence.
- **SC-003**: An observed editor invocation reads the installed skill, at least one relevant bundled
  reference/example and its declared external instruction without source-checkout fallback.
- **SC-004**: Missing/corrupted inputs and occupied targets have recorded outcomes; no force overwrite,
  unrelated consumer mutation, tool installation or publication occurs without explicit authorization.
- **SC-005**: The final report distinguishes all four gates: generation, catalog discovery,
  installation and editor/resource loading; no static-only check closes a runtime gate.

## Assumptions

- Use the already pinned Spec Kit 1.2.3 Copilot skills-mode integration and installed runtimes;
  adopting a different CLI release or integration requires a separate decision.
- Use `patterns-ports-and-adapters` as the first root, continuing the earlier local archive pilot;
  its authored version is not a published release or a rights-clearance decision.
- Local-only artifact hosting and consumer verification are sufficient for this pilot. Public
  catalog hosting, release assets, signing and legal clearance remain separate future gates.
- Installation location and retention are explicit verification approvals, not a decision about
  the future general installer's workspace/profile scope or recovery contract.
- This specification starts feature 003; completed features 001 and 002 remain unchanged.
