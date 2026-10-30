---
name: docs-adr
description: 'Create, refine, review and supersede architecture decision records (ADRs) and architecture design proposals. Use for evidence-backed decisions under docs/, local ADR drafts, GitHub issues labelled adr, alternatives and tradeoffs, source deep links, and turning a design discussion into a durable decision record.'
---

# ADR Authoring

Produce a durable explanation of an architectural choice: what problem it solves, which alternatives
were considered, why the recommendation fits, and what would justify revisiting it. Default to a
local record; a design discussion is not authorization to implement, commit or publish it.

## Authorities and Boundaries

- Follow the [Markdown instructions](../../instructions/markdown.instructions.md) and
  [Mermaid instructions](../../instructions/markdown.mermaid.instructions.md).
- Use the [GitHub issues and pull requests skill](../github-issues-and-pull-requests/SKILL.md)
  for issue discovery, effective templates, metadata and remote verification.
- Apply the [repository privacy skill](../repository-privacy/SKILL.md) before public content.
  Related repositories can be evidence without being safe to identify in the published record.
- Use applicable domain skills for technical contracts. Do not copy their conventions into an ADR
  or make one session's technology choices mandatory for unrelated designs.

## Modes and Persistence

| Mode | Outcome |
| --- | --- |
| `draft` | Research and write a local proposed ADR or explicitly requested design document |
| `update` | Refine an existing proposal, integrating new requirements across affected sections |
| `review` | Report evidence, consistency, alternatives and validation gaps without editing |
| `supersede` | Write a replacement decision and link its relationship to the accepted record |
| `issue` | Prepare locally, then create/update an issue when that remote operation is authorized |

Use the repository's existing ADR path and numbering. Otherwise default to
`docs/adr-0001-<short-topic>.md`, choosing the next unused number. Do not relocate existing records
or invent a new documentation hierarchy merely to fit this skill.

Persistence choices are a local document, a GitHub issue with the exact `adr` label, or both:

- With no explicit remote request, persist under `docs/`. Do not create an issue automatically.
- For an issue-only request, prepare the draft locally in session storage, then publish the
  authorized issue; do not create a second tracked document unless requested.
- When both are requested, identify one canonical record. Prefer the document as the decision and
  the issue as the discussion/tracking entry, linking them instead of maintaining two independently
  edited full copies. If the issue is canonical, the document should point to it.
- Resolve genuinely ambiguous audience, ownership, canonical location or remote targets through
  one focused question. Do not re-ask choices the caller already supplied.

## 1. Establish Scope and Evidence

1. Resolve the target repository, current branch, working-tree changes, audience and instructions.
   Preserve unrelated edits and remain on the current branch unless a separate authorized Git
   operation requires otherwise.
2. Read existing ADRs, design indexes and related open decisions before adding another. For a
   workspace request, use the active workspace definition rather than every neighboring clone.
   Inspect representative records; generalize useful practices, not private identities or details.
3. State the decision boundary, goals, non-goals, constraints and actual consumer. Separate
   deployment configuration, mutable operational controls and domain data where relevant.
4. Inspect existing implementation, public contracts, registration, dependencies and tests.
   Distinguish a declared interface from a wired implementation, and the local checkout from a
   released package. Reuse prior art only after verifying its behavior and suitability.
5. Check version-relevant official sources when a claim depends on platform semantics. Record
   measurements with conditions, assumptions as assumptions and unresolved facts as open questions.
   Do not substitute an attractive architecture diagram for evidence.

## 2. Deep-Link the Evidence

Important factual claims and integration points should link directly to their evidence, not just
to a repository home page. Include the relevant projects, source files and defining interfaces
inside the target and in safely referenceable related repositories, plus official platform sources.

| Evidence | Link policy |
| --- | --- |
| Same-repository source from a document | Verified relative path to the defining project/file/interface; add a useful heading or source reference where supported |
| Same-repository source from an issue | Verified GitHub file/symbol link; no workstation paths |
| Related-repository implementation | Verified remote file/interface link at a safe, available ref; check visibility before naming or linking |
| Exact behavior used to justify a decision | Commit permalink when the examined revision matters |
| General integration reference | Default-branch link when it already contains the target |
| External behavior or limits | Specific official vendor/framework page, matching the relevant version where possible |
| Proposed/new API or unpublished file | Label it proposed/local-only; do not fabricate a resolving remote link |

Verify definitions, link destinations and anchors. A local file's existence does not prove it is on
the remote default branch. Never send private source or identifiers to external search/link-checking
services. Apply the shared cross-visibility rules for issue references and publication; in public
records describe confidential relationships generically rather than leaking them in link targets.

Place links next to the claim and keep a small source/evidence table when it helps. A bibliography
of home pages is not a substitute for source deep links. Mark inaccessible/unverified sources
explicitly instead of treating them as confirmed.

## 3. Write the Decision, Not a Product Promise

Use the [ADR outline](./assets/adr-template.md), adapting it to the repository's existing format.
Keep the outcome understandable without opening every supporting link.

- Mark a recommendation **Proposed** until the decision owner accepts it. Track Accepted,
  Rejected and Superseded explicitly; an implementation checklist is not acceptance. Keep decision
  status separate from implementation progress, including partial delivery and blocked work.
- Compare credible alternatives, including keeping the current design. Explain rejected options,
  tradeoffs, dependency/ownership costs and what evidence would change the recommendation.
- Keep current behavior, proposed behavior, implementation progress and stretch goals distinct.
  Proposed package/API names are illustrative, not installable products.
- Define contracts before storage/transport: types, scope, lifecycle, validation and the component
  that enforces each guarantee. Example environment names, counts or deployment layouts are not
  fixed enumerations or requirements unless explicitly chosen.
- For stateful/distributed changes, identify the authority, transaction/concurrency boundary,
  propagation and consistency model, failure policy, recovery and history/rollback semantics.
  Distinguish durable acceptance from application activation; a cache or notification is not
  automatically a source of truth or proof that every replica applied a change.
- Address operational ownership, authorization, sensitive-data handling, compatibility,
  migration/cutover and rollback where relevant. State practical limits, not unsupported absolutes
  such as instantaneous convergence or tamper-proof audit history.
- Give measurable acceptance evidence tied to the requirement, not a proxy: actual consumer/host
  behavior, supported backend/layout combinations and automated runner wiring when applicable.
  A test file, nominal workflow input or successful build does not prove execution or behavior.
- Record prerequisites, phase boundaries and intentionally deferred work. Keep stretch goals
  optional and give them a trigger/acceptance gate instead of speculative implementations.
  For substantial proposals, use stable requirement/decision identifiers to connect constraints,
  implementation steps and validation evidence without creating a separate tracking receipt.
- During implementation, update the canonical ADR checklist at each phase boundary. Check off only
  verified outcomes and link their evidence; split partially delivered criteria rather than marking
  a whole phase complete. Keep local validation, remote CI execution and live rollout distinct.
- Keep the ADR focused on one decision. Put substantial design exploration, schemas, detailed
  test matrices or runbooks in supporting `docs/` material only when useful/requested, and link it.
  Do not grow every ADR into a tutorial or reproduce application implementation details.

## 4. Evolve a Proposal Without Contradictions

Treat follow-up requirements as edits to the existing proposal, not append-only amendments.
Update the summary, alternatives, dependency boundaries, data model, diagrams, failure semantics,
UI/API contract, acceptance criteria and open questions that the change actually affects.
Remove superseded assumptions and duplicate wording in the same pass.

Do not silently rewrite an accepted decision's rationale/outcome. Record a changed decision in a
new ADR, mark the relationship and preserve the historical record. Status/link updates and factual
errata can be annotated without pretending the old decision was always the new one.
Record significant implementation deviations and their reasons in a linked follow-up or clearly
dated implementation note; distinguish a shipped compromise from the original accepted choice.
Do not assign a decision owner, approval, execution result or completion status without evidence.

## 5. Optionally Persist as a GitHub Issue

1. Require an explicit request to create/update the issue; once given, use the non-interactive
   GitHub workflow without another confirmation form. Search for an existing matching ADR issue
   before creating a duplicate.
2. Resolve repository visibility, effective issue template, supported issue types and labels.
   Fit the ADR sections into that template and use the closest supported native issue type;
   the `adr` label supplements rather than replaces type metadata.
3. Apply the exact `adr` label. Create it only when label administration is authorized/in scope.
   If unavailable and creation is not authorized, report the blocker rather than silently using
   another label or omitting it.
4. Review the complete title/body, links and metadata against the publication boundary. Replace
   local paths with safe remote links and preserve Proposed/Accepted status independently of
   whether the issue is open or closed.
5. Publish the authorized content, retrieve it again, and verify body, status, links and `adr` label.
   Return the issue URL and connect the canonical local record when both surfaces are in scope.
   Never claim issue creation from a local draft or request payload alone.

## 6. Validate and Report

- Check consistency against the caller's requirements and the evidence. Identify uncertainty,
  intentionally omitted sections and unresolved decisions instead of filling gaps with guesses.
- Verify local links, relevant remote references and diagram semantics; use existing repository
  documentation checks. Ask before running tests, including documentation/customization tests.
  Check that selected tests actually ran; a zero-match filter is not success. Obtain approval
  before widening a test run beyond the authorized scope.
- Do not execute application examples, change infrastructure, implement the proposal, commit,
  push or create remote issues merely to validate a document.
- Report the local record and/or verified issue URL, decision status, canonical location,
  validation performed and remaining blockers. Distinguish saved, committed and published.

## References

- [Microsoft guidance on architecture decision records](https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record)

## Maintaining This Skill

- Keep persistence/label steps aligned with the GitHub issue skill, effective templates and
  actual issue/label API behavior; do not duplicate that skill's command recipes.
- Recheck official ADR guidance, source permalink/anchor behavior and local template conventions
  when observed practice changes.
- Capture reusable lessons from later ADRs here or in the outline, while keeping domain-specific
  decisions and confidential examples out of the shared workflow.
