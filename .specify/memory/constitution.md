# Shared Copilot Library Constitution

## Core Principles

### I. Canonical Native Source and Single Ownership

Reusable guidance MUST have one canonical owner in the native customization library. Amend the
owning instruction or skill instead of maintaining competing copies. Consumer repositories MUST
reference shared guidance and retain only their specific rules. Approved source moves MUST
preserve aligned discovery identities, links and supporting resources. This keeps corrections
effective across consumers without requiring a second authored library.

### II. Scoped Discovery and Progressive Loading

Customizations MUST use their native discovery metadata and portable workspace-relative scope.
Instructions MUST state applicability; skills MUST describe when to invoke their workflow.
Keep discovery descriptions concise and load task-specific guidance and resources when relevant,
rather than injecting the whole library. Changes to discovery paths or loading behavior MUST
distinguish static checks from evidence in the intended editor or agent harness. Installed files
alone do not prove discovery or context loading.

### III. Evidence-Based, Usable Guidance

Guidance MUST identify prerequisites, actionable steps, approval boundaries and observable
outcomes. Technical claims MUST be grounded in inspected implementation, authoritative references
or recorded validation; label proposals and unverified behavior explicitly. Keep supporting
examples and resources consistent with the guidance that owns them. Correct durable lessons in
that owner rather than creating another rule source. This makes guidance usable without implying
that a static check establishes runtime compatibility.

### IV. Explicit Metadata and Separate Generated Outputs

For opted-in components, the [skill-library authority] owns the format-neutral metadata contract,
schemas and dependency validation. Authored identity and dependency declarations MUST remain in
their authoritative records, not be repeated in prose or an independently maintained index.
Ordinary hyperlinks MUST NOT be inferred as dependency declarations. Any generated distribution
MUST derive from canonical content and metadata, not become a second authored source. Generated
inventory, provenance and consumer installation state MUST remain distinct from authored intent.
This boundary does not require packaging, installation or publication to be implemented.

### V. Authority-Governed Approval and Validation

Execution and validation MUST follow the [shared workflow authority] and [GitHub authority].
Apply the relevant scoped instructions and owning skills instead of restating their approval,
privacy, test, branch or release rules here. Record the checks actually performed and any
unverified requirements. Constitution adoption and design approval MUST NOT be treated as
authorization for feature implementation or delivery operations.

## Authority and Scope

The [repository instructions] own library layout and authoring conventions; the [README] owns
consumer orientation. Shared cross-cutting and scoped instructions remain authoritative in their
domains. This constitution governs this repository's Spec Kit work by reference to those owners;
it does not supersede them or create a separate execution policy. Resolve contradictions with the
owning authority before proceeding.

[ADR 0001] remains In Progress. Its implemented metadata and local version-preparation context
does not make the remaining distribution proposals accepted rules. Unimplemented packaging,
installation and publication MUST remain identified as such; this adoption provides no delivery
guarantees and requires no migration from native consumption.

## Review and Compliance

Plans and change reviews MUST check relevant principles, identify the owning instructions and
skills, and state how the proposed change preserves native use and single ownership. Review
metadata changes against the existing contract rather than inventing another dependency graph.

Validation scope and execution approvals come from the shared authorities. Reports MUST separate
static content checks, approved executable checks and observed consumer behavior. Missing or
unrun checks MUST be disclosed, not reported as passing. Any proposed exception MUST name the
affected principle, explain its rationale and impact, and receive maintainer approval before
implementation; a conflicting shared rule requires resolution in its owning authority.

## Governance

Amendments MUST document the proposed wording, rationale, affected principles and consumer impact,
including a migration plan when behavior changes. Obtain explicit maintainer approval, update this
constitution and its amendment date, and identify affected guidance for separately authorized
follow-up. Do not silently rewrite dependent authorities or treat an amendment as implementation
approval. Reviews MUST assess compliance and record unresolved exceptions or validation gaps.

Constitution versions use semantic versioning: MAJOR for incompatible principle or governance
removals or redefinitions; MINOR for added principles or materially expanded guidance; PATCH for
clarifications or corrections without changed obligations. Preserve the original ratification
date and use the amendment date for subsequent revisions. This version is the first adoption of
the previously unratified scaffold, not a bump from an earlier constitution or a component release.

[repository instructions]: ../../.github/copilot-instructions.md
[shared workflow authority]: ../../.github/instructions/workflow.instructions.md
[GitHub authority]: ../../.github/instructions/github.instructions.md
[skill-library authority]: ../../.github/skills/skill-library/SKILL.md
[README]: ../../README.md
[ADR 0001]: ../../docs/adr-0001-copilot-spec-kit-distribution.md

**Version**: 1.0.0 | **Ratified**: 2026-10-27 | **Last Amended**: 2026-10-27
