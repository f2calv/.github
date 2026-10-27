# Feature Specification: Packaging Inventory Preview

**Feature ID**: `001-packaging-inventory-preview`

**Created**: 2026-10-27

**Status**: Draft

**Input**: User description: "Enhance skill-library with a read-only packaging-inventory preview for selected skills and their required and explicitly selected optional dependency closures. Reuse existing metadata validation. Identify committed payload files, external instructions and inherited notices, with inclusion reasons and source commit. Exclude archive creation, installation, version changes and publication."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Review a Committed Inventory (Priority: P1)

A library maintainer selects native skills and reviews the complete set of committed files
needed by those skills and their required dependencies, without creating a package or changing
the repository. A dependency closure means the selected skills plus every prerequisite reached
through included dependency relationships.

**Why this priority**: An attributable inventory is the smallest useful review outcome before
any later packaging decision.

**Independent Test**: Review a known committed library with one selected root, a transitive
required dependency and a resource file. Compare the preview against that commit's files and
confirm the working tree is unchanged.

**Acceptance Scenarios**:

1. **Given** a valid committed library and a selected native skill, **When** the maintainer
   previews it, **Then** the result identifies the root, all transitive required dependencies,
   their exact declared versions, derived native folders and eligible committed payload files.
2. **Given** staged, unstaged, ignored or untracked local changes, **When** the maintainer
   previews the current commit, **Then** only that commit's metadata and content determine the
   result, the source commit is explicit, and the result states that local changes are excluded.
3. **Given** a different available local commit is chosen, **When** the preview succeeds,
   **Then** declarations, defaults, dependency versions and file bytes all refer to that one
   resolved commit, not a mixture with the checkout or another revision.
4. **Given** no roots are supplied, **When** the preview runs, **Then** every opted-in skill
   in the chosen commit is a root, preserving the existing validation selection default.

### User Story 2 - Review Explicit Optional Dependencies (Priority: P2)

A maintainer includes only deliberately selected optional relationships and can explain why
each dependency and shared file belongs in the resulting inventory.

**Why this priority**: Optional content must remain a deliberate choice rather than silently
expanding every preview to the whole library.

**Independent Test**: Compare previews of a known root with and without a reachable optional
selection whose target has a required dependency. Verify the added closure and every reason.

**Acceptance Scenarios**:

1. **Given** declared but unselected optional relationships, **When** a root is previewed,
   **Then** those relationships add no components or files; a target reached independently by
   a required relationship or another root remains included for that reason.
2. **Given** an explicitly selected reachable optional relationship, **When** previewed,
   **Then** its target and transitive required closure are included. Further optional
   relationships are included only when separately selected and reachable, including through
   another selected optional relationship.
3. **Given** two roots or dependency paths share a component or file, **When** previewed,
   **Then** each component and repository-relative file appears once while retaining all
   applicable root, dependency and file inclusion reasons.
4. **Given** an unknown, duplicate or unreachable optional selection, **When** previewed,
   **Then** the entire request fails with an actionable diagnostic and no successful partial
   inventory is presented.

### User Story 3 - Inspect Notices and Review Boundaries (Priority: P3)

A maintainer distinguishes internal skill content from declared external instructions and
notices, and sees effective license declarations without mistaking an inventory for legal
clearance or release approval.

**Why this priority**: Reviewers need to see shared obligations and the limits of the preview
before considering a separate distribution workflow.

**Independent Test**: Review a committed selection with repository notice defaults, a component
license override, an additional notice and an external instruction shared by two components.
Verify attribution and failure when a required declared file is absent.

**Acceptance Scenarios**:

1. **Given** shared notice defaults and component additions, **When** previewed, **Then** each
   selected component shows its effective license and inherited plus additional notices, and
   the file inventory retains each owning component and declaration source.
2. **Given** a declared external instruction or notice, **When** its component is included,
   **Then** that committed file is mandatory inventory content with its declared kind and
   loading purpose; it is not treated as an optional dependency.
3. **Given** missing mandatory content or any existing metadata validation failure,
   **When** previewed, **Then** the request fails without a success result or silently omitted
   required files, and identifies the corrective category without exposing file contents.
4. **Given** a successful or failed preview, **When** it finishes, **Then** tracked files,
   untracked files, index, branch, commits and tags are unchanged, and no payload script or
   declared tooling has been executed or installed.

### Edge Cases

- An unknown or unconverted root fails; unconverted directories are not inferred components.
- Empty root selection uses all opted-in skills; an empty opted-in catalog fails under the
  existing validator. Repeated root names denote the same root, not duplicate output.
- A required cycle anywhere in the opted-in catalog or a cycle involving selected optional
  relationships fails according to the existing validator; unselected optional cycles do not
  become a new failure category.
- Invalid metadata, unavailable dependency targets, exact-version mismatches, unsafe paths,
  links, case collisions and duplicate declarations retain existing validation outcomes.
- Shared paths across different selected components are deduplicated in output, not confused
  with invalid duplicate declarations within a component's effective declarations.
- A file deleted or changed locally still uses its committed content; a file present only
  locally cannot satisfy a committed declaration. Local-only metadata cannot opt in a skill.
- An unavailable or ambiguous source revision, missing committed content, or a required file
  excluded from eligibility fails the request rather than falling back to working files.
- Binary assets and eligible resource files are inventory entries without being executed,
  rendered or rewritten. Ordinary hyperlinks do not add dependencies or external payload.
- An invalid unselected opted-in record still fails existing catalog-wide validation, but
  valid unselected components do not contribute payload or notices to the selected inventory.

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: The preview MUST accept selected native skill roots and explicit optional selections
  using the existing validation selection contract, including all opted-in roots when omitted.
- FR-002: The preview MUST resolve one available local committed revision, defaulting to the
  current commit at invocation, and identify its full source commit. All inventoried content,
  metadata, defaults and dependency decisions MUST derive from that same committed snapshot.
- FR-003: The preview MUST reuse the [existing metadata validation authority] and its bundled
  [metadata schema] and [defaults schema], rather than redefine declarations, infer edges from
  hyperlinks or maintain a second graph. Its strict parsing, catalog-wide validation, exact
  pins, native alignment, path safety and cycle rules MUST retain their existing semantics
  when applied to the committed snapshot. Inventory scope MUST remain the selected closure.
- FR-004: The result MUST include every transitive required dependency and only explicitly
  selected reachable optional relationships, with the required closure of each selected
  optional target. Optional selection identifiers MUST follow the existing contract.
- FR-005: The result MUST identify selected roots, explicit optional selections and each
  included component's stable identity, declared version and derived native folder and
  entrypoint, preserving all root and dependency inclusion reasons.
- FR-006: The inventory MUST contain all eligible committed regular files beneath included
  skill directories, including metadata, internal references, examples, scripts and assets,
  without requiring authored resource lists. It MUST exclude unselected component content,
  untracked or ignored inputs and unrelated repository files unless separately required by
  an included component's external-file or notice declarations. Ignore eligibility MUST use
  the chosen snapshot's repository rules, not local or user-level ignore overrides.
- FR-007: The inventory MUST include every included component's declared external files and
  inherited and additional notice files from that commit. It MUST preserve effective license
  declarations and their inheritance or override sources without inferring third-party rights.
- FR-008: Each unique repository-relative file MUST appear once, attributed to the source
  commit and all including components and reasons. Reasons MUST distinguish implicit internal
  content, declared external instruction or notice, inherited notice and component-added
  notice; external declarations MUST retain their kind and loading purpose. Shared-file
  deduplication MUST NOT weaken existing duplicate-declaration validation.
- FR-009: Invalid roots or optional selections, unavailable source input, existing validation
  failures and missing or ineligible mandatory files MUST produce a clear failure with an
  actionable category, not a successful partial inventory. Diagnostics MUST NOT echo payload
  contents or credentials. Missing prerequisites MUST be reported, not installed.
- FR-010: Identical source commits, selections and validation rules MUST yield the same
  component membership, file membership and inclusion reasons in a stable review order.
- FR-011: Preview success and failure MUST leave repository files, index and Git state
  untouched. The preview MUST NOT execute payloads or advisory tooling, access the network,
  create archives, install content, change versions or pins, create tags, or publish anything.
  Any temporary read-only inspection material MUST be outside the worktree and cleaned up.
- FR-012: The result MUST distinguish a committed inventory preview from a built package,
  immutable release/provenance record, rights clearance, installation or publication approval.
  It MUST state that uncommitted changes are excluded, so reviewing a preview cannot be
  mistaken for reviewing the current working content.

### Key Entities *(include if feature involves data)*

- Source snapshot: One resolved commit supplying the declarations and committed file content
  for the whole preview, independent of staged or working files.
- Selection: Native skill roots and explicitly chosen optional relationship identifiers.
- Included component: An existing opted-in identity and version with its native source
  location, effective license/notices and all selection or dependency reasons.
- Inventory entry: One committed repository-relative file, its source commit, owning
  components, content category and all applicable inclusion reasons.
- Preview outcome: Either a complete review inventory with its scope limitations or an
  actionable failure that cannot be confused with partial success.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: For each accepted reference selection, reviewers can account for 100% of expected
  committed payload, external instruction and notice files, with zero unrelated inclusions.
- SC-002: Every included component and file has a source commit and all applicable inclusion
  reasons; each unique file appears exactly once even when shared by multiple components.
- SC-003: In reference cases with required chains and nested optional selections, 100% of
  required relationships and explicitly selected reachable optional relationships are covered;
  zero components are added solely through an unselected optional relationship.
- SC-004: Every specified invalid-selection, validation and missing-source case produces a
  failure, with zero cases misrepresented as a complete or successful partial inventory.
- SC-005: Successful and failed previews cause zero repository or Git-state changes and zero
  archive, installation, version-change or publication actions.
- SC-006: Reviewers can identify the chosen commit, excluded local changes, effective notice
  sources and lack of release or rights approval directly from each successful result.
- SC-007: Repeated previews of the same committed input and selections present identical
  membership and reasons in the same review order, regardless of unrelated local edits.

## Assumptions

- The audience is library maintainers reviewing proposed distribution content. Packaging
  remains unimplemented; these requirements describe an enhancement, not current capability.
- Defaulting to the current commit and permitting an explicitly chosen available local commit
  provides reproducible attribution without rejecting an otherwise dirty checkout. No local
  edits are incorporated, and no fetch or source checkout change is required.
- The existing [skill-library authority] owns authored metadata and selection semantics;
  the preview adds committed inventory reporting, not a new schema or independent validation
  policy. Existing catalog-wide checks remain prerequisites even for a narrower payload.
- Existing validation prerequisites must already be available. The preview does not provision
  them, execute advisory tools or alter their configuration.
- Eligibility combines committed presence, snapshot repository ignore rules and the existing
  file-safety contract. If a selected component's entrypoint, metadata or mandatory declared
  file is ineligible, the request fails; optional non-payload working files cannot replace it.
- Repository-relative path identity follows existing collision rules. Source commit and
  reasons are sufficient for this review slice; file hashes, artifact digests, release history
  verification and durable rights evidence belong to later separately authorized work.
- Notice and license reporting reflects declarations only. It is not a legal audit, a
  redistribution guarantee or proof that a future package is safe to publish.
- Archive assembly, installation ownership, command wrappers, version preparation, metadata
  edits, release snapshots, catalogs, publication and performance benchmarking are out of scope.

[existing metadata validation authority]: ../../.github/skills/skill-library/scripts/Invoke-Validation.ps1
[metadata schema]: ../../.github/skills/skill-library/skill-metadata.schema.json
[defaults schema]: ../../.github/skills/skill-library/repository-defaults.schema.json
[skill-library authority]: ../../.github/skills/skill-library/SKILL.md
