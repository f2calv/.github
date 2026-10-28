# Feature Specification: Deterministic Skill Archives

**Feature**: `002-deterministic-skill-archives`

**Created**: 2026-10-27

**Status**: Draft

**Input**: Create a reproducible local archive for one selected skill and its required dependency
files. Never bundle optional related skills merely because they are recommended or selected.
A future extension will offer those skills as separate downloads and installations. Continue on
the existing branch while the preceding pull request is reviewed; leave all new work uncommitted
for transfer to the next branch after that pull request is merged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Package One Skill Without Optional Bundles (Priority: P1)

A maintainer selects one skill at a committed source revision and creates a local archive containing
that skill's eligible files, its complete required dependency closure, external instruction files
and applicable notices. Optional relationships remain recommendations, not payload selections.

**Why this priority**: A useful package must deliver the selected skill's prerequisites without
silently installing unrelated functionality or turning recommendations into bundled dependencies.

**Independent Test**: Package a synthetic root with a required chain, a shared required dependency
and an optional related skill that has its own required dependency. Inspect every archive member
against the required-only inventory and confirm that no optional-only content appears.

**Acceptance Scenarios**:

1. **Given** a valid root with required dependencies, **When** the maintainer packages that root,
   **Then** every eligible required-only payload file appears exactly once with its committed bytes.
2. **Given** an optional relationship to another skill, **When** the root is packaged, **Then** that
   optional target and its dependencies contribute no payload unless independently required by the
   root's required closure; optional declarations may remain in metadata without carrying payload.
3. **Given** a target reachable through both required and optional relationships, **When** the root
   is packaged, **Then** it is included once for the required relationship, not as an optional bundle.
4. **Given** no root, multiple roots or an optional-selection request, **When** packaging is requested,
   **Then** the operation fails clearly rather than building a library-wide or combined archive.

### User Story 2 - Rebuild Identical Archive Bytes (Priority: P2)

A maintainer can rebuild an archive from recorded inputs and obtain exactly the same bytes and
artifact digest. Local edits, output location, wall-clock time and temporary directory names do
not affect the result.

**Why this priority**: Repeatable artifacts let reviewers verify what was built and distinguish
content changes from incidental differences between build environments.

**Independent Test**: Build the same synthetic package twice in separate temporary contexts with
different creation times and output paths, then compare complete archive bytes and digests.

**Acceptance Scenarios**:

1. **Given** identical committed inputs and the same recorded build contract, **When** two builds
   run independently, **Then** their archive bytes and artifact digests are identical.
2. **Given** dirty, staged, deleted-local or untracked source files, **When** a recorded commit is
   packaged, **Then** only that commit's eligible bytes and source modes determine the payload.
3. **Given** changed eligible payload bytes, **When** that changed source is packaged, **Then** the
   corresponding member bytes and artifact digest change.
4. **Given** a different or unsupported builder contract, **When** reproducibility is reported,
   **Then** the report distinguishes the inputs instead of claiming unconditional equivalence.

### User Story 3 - Inspect Build Evidence And Fail Safely (Priority: P3)

A maintainer can inspect generated evidence connecting archive members to the source commit,
selected root, exact required closure and effective license/notice declarations. Invalid inputs
or output failures do not produce a misleading successful package or overwrite existing files.

**Why this priority**: Reproducibility does not establish rights, authenticity or installation
safety. Exact-content evidence and conservative writes are needed before any later delivery gate.

**Independent Test**: Compare generated evidence with the archive and inventory, then exercise
invalid source, unsafe paths, existing destinations and failed writes while inspecting caller state.

**Acceptance Scenarios**:

1. **Given** a successful build, **When** evidence is inspected, **Then** every payload member maps
   to its source path, committed mode, content digest and inclusion reasons, with no unexplained files.
2. **Given** required notices or external instructions, **When** a package is built, **Then** they
   are included and attributed without inferring rights clearance from a license declaration.
3. **Given** invalid metadata, unavailable required inputs, unsafe paths or conflicting member names,
   **When** packaging is requested, **Then** it fails before reporting any completed artifact.
4. **Given** an existing destination or a failure during writing, finalization or cleanup, **When**
   packaging runs, **Then** it does not overwrite caller-owned files, report partial success or
   silently discard unexpected concurrent data; any retained owned recovery files are identified.

### Edge Cases

- Required chains and diamonds, including multiple owners of the same notice or external file.
- Optional targets with their own required or optional dependencies, including a target also
  independently reachable through required edges.
- Zero or multiple roots, repeated roots, and attempts to pass inventory optional selections
  through the packaging interface.
- A source commit differing from the invoked trusted validator and builder; historical scripts
  remain inert payload, never executable build tooling.
- Ignored mandatory files, unsupported source modes, symbolic links, path traversal, case collisions,
  and collisions between payload paths and generated evidence paths.
- Empty files, binary data, executable files, non-ASCII names and differing source line endings.
- Missing local objects, invalid catalog records and exact-version mismatches, including optional
  declarations checked by the existing catalog validator without being added to payload.
- Source changes during inspection, output paths inside managed source content, existing outputs,
  failed writes, cleanup failures and concurrent destination creation.
- Rebuilds across advertised runtime/platform combinations; unverified combinations are not
  covered by the reproducibility claim.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Packaging MUST require exactly one explicit opted-in native skill root and resolve one
  locally available source commit. It MUST NOT inherit the inventory preview's all-roots default.
- **FR-002**: Packaging MUST reuse existing metadata validation, eligibility rules and required-only
  committed inventory membership rather than maintain another dependency resolver or infer edges
  from Markdown links. Existing catalog validation MUST NOT be weakened to ignore invalid records.
- **FR-003**: The payload MUST contain the selected root's eligible internal files, the transitive
  required closure's eligible files, declared external instructions and applicable inherited,
  component and external notices. Shared source files MUST appear once with all relevant attribution.
- **FR-004**: Packaging MUST NOT accept optional selections or add optional-only targets or their
  dependencies to the payload. A target independently required by the required closure MUST still
  be included. Authored optional relationship declarations MAY remain as advisory metadata only.
- **FR-005**: Payload bytes and source modes MUST come from the resolved commit, not the working
  tree or index. Historical payload code MUST NOT execute. Temporary inspection MUST preserve the
  caller's source files, index, HEAD, refs and local Git configuration.
- **FR-006**: The archive layout MUST retain distinct native skill directories and the identity of
  external files and notices. Every member MUST be either an eligible payload file or explicitly
  identified generated evidence. Unsafe paths, unsupported modes and ambiguous names MUST fail.
- **FR-007**: Identical recorded build inputs under the supported build contract MUST produce
  byte-identical archives. Entry ordering, timestamps, modes, paths, encoding, generated evidence
  and compression behavior MUST be controlled; host names, user names and temporary paths MUST
  NOT leak into artifacts or affect their bytes.
- **FR-008**: Generated build evidence MUST identify the source commit, selected root, exact required
  component versions, trusted validation/build contract identity, payload paths, content digests,
  committed modes, inclusion reasons and effective license/notice sources. It MUST be derived,
  not maintained as a second authored metadata or dependency source.
- **FR-009**: Successful output MUST include an artifact digest that can be independently verified.
  An artifact MUST NOT contain its own final digest; the evidence design MUST avoid circular
  hashing and distinguish generated evidence from source payload.
- **FR-010**: Persistent output MUST require an explicit destination outside managed source content.
  Packaging MUST refuse existing destinations, avoid blind overwrites during concurrent creation,
  and report success only after all promised outputs are finalized and temporary cleanup succeeds.
  Failure recovery MUST affect only operation-owned files and disclose retained recovery material.
- **FR-011**: Failures MUST return a non-success result with an actionable category without echoing
  payload contents or secrets. No completed artifact or digest MUST be reported on partial failure.
- **FR-012**: Packaging MUST perform no network access, prerequisite installation, consumer install,
  version preparation, tag creation, release creation or publication. Payloads MUST NOT trigger
  hooks, filters or application code. Source declarations MUST NOT be changed to accommodate a build.
- **FR-013**: Build evidence MUST distinguish declared license/notice information from redistribution
  approval and authenticity. Existing exact-content and rights-review boundaries MUST remain;
  producing a local artifact MUST NOT be represented as permission to publish or install it.
- **FR-014**: The existing read-only inventory preview MUST retain its independently useful optional
  closure inspection. Its combined preview results MUST NOT be treated as a single-package payload.
- **FR-015**: User guidance MUST describe the supported build contract, output inspection and digest
  verification, record actual platform evidence and identify unverified combinations. Native use
  MUST remain available without packaging or a consuming extension.

### Key Entities *(include if feature involves data)*

- Package root: one selected native skill with its declared distribution identity and version.
- Required payload inventory: committed eligible files and attribution reachable through required
  relationships only, including external instructions and applicable notices.
- Build contract: the identified rules, builder and settings defining supported reproducibility.
- Archive: the generated local artifact containing the required payload and any declared build
  evidence, never optional-only skill payloads.
- Build evidence: derived source, dependency, license/notice and per-member integrity information;
  separate from authored intent and future consumer installation state.
- Artifact digest: externally recorded integrity value of the completed archive, not a signature
  or a redistribution approval.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Inspected packages match the required-only eligible inventory exactly: every required
  payload file appears once and zero optional-only or unrelated payload files appear.
- **SC-002**: Two independent builds with identical recorded inputs produce identical complete
  archive bytes and artifact digests across each advertised supported build environment.
- **SC-003**: Every payload member has verifiable source, content, mode and inclusion attribution;
  generated members are explicitly distinguished and every promised digest verifies independently.
- **SC-004**: Negative scenarios for invalid input, unsafe members, existing output and failed
  finalization return failure, preserve caller-owned state and never report a completed package.
- **SC-005**: Dirty source state, different output paths and different build times do not alter
  archive bytes for a fixed source and build contract; changed eligible content changes its member
  bytes and artifact digest.
- **SC-006**: Builds perform zero downloads, installations, version edits, Git history/ref changes
  or publication operations. Documentation makes no unsupported Windows, rights or loader claims.

## Assumptions

- This increment produces local artifacts only. Extension discovery, optional-skill prompts,
  separate downloads, installation, upgrades, conflict resolution and release publication are
  future work, not capabilities supplied by this archive builder.
- The preceding [inventory feature](../001-packaging-inventory-preview/spec.md) supplies reusable
  read-only source inspection. Its completed contract and verification records are not rewritten.
- The [owning skill](../../.github/skills/skill-library/SKILL.md) retains authority for authored
  metadata and validation; the [constitution](../../.specify/memory/constitution.md) governs source
  ownership and approval. No new sidecar schema is assumed.
- Format, member layout, digest representation, reproducible builder settings and output recovery
  mechanics will be resolved during planning before implementation. This specification does not
  establish compatibility with any existing Spec Kit extension loader.
- Supported execution initially targets the observed Linux dev container. Native Windows and
  cross-runtime equivalence require separately approved observed verification; the previous feature's
  Windows waiver does not establish a passing check for this increment.
- Tests need explicit approval. The preceding PR is now merged and the separately authorized
  working branch is checked out. Planning remains uncommitted; no commits, pushes or further
  branch changes are authorized by this feature request.
