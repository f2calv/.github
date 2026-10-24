# ADR Outline

Use the target repository's established format first. Otherwise adapt the outline below.
This is an authoring aid, not a requirement to fill every optional heading. Remove placeholders and
template commentary from the completed record. Ordinary ADR documents do not use YAML frontmatter.

The decision should stand alone. Move substantial supporting design material to a linked document
only when the scope warrants it; do not create empty companion files or an index for one record.
For an issue, adapt these decision elements to the repository's effective issue template.

```markdown
# ADR <number>: <Decision title>

**Status:** Proposed.
**Date:** <YYYY-MM-DD>.
**Scope:** <Decision boundary and affected capabilities>.

## Context and Problem

<What needs to change, who needs it and why the present design is insufficient.
Separate source-confirmed facts, requirements, assumptions and unknowns.
Deep-link the relevant existing projects, files, interfaces and official sources.>

## Goals and Constraints

<Required behavior and quality attributes; non-goals and constraints that materially shape
the choice. Explain whether names, counts and deployment shapes are examples or requirements.>

## Options Considered

| Option | Benefits | Costs and risks | Assessment |
| --- | --- | --- | --- |
| Keep the current design | <Benefits> | <Costs> | <Reason> |
| <Alternative> | <Benefits> | <Costs> | <Reason> |

## Proposed Decision

<State the recommendation and rationale directly. Use "Decision" when accepted.
Identify the enforcing component, authority/ownership and public contract.
Label illustrative names and unimplemented capabilities explicitly.>

## Consequences

<Benefits and negative consequences, including dependency and operational cost.
State relevant consistency, failure/recovery, security and migration/rollback boundaries.
Keep this decision-focused; link detailed supporting design rather than copying it.>

## Validation and Delivery

<Measurable acceptance criteria, actual consumer/backend coverage and execution/CI wiring.
Separate planned tests from observed results. Record prerequisites and deferred work/triggers.
Omit phased delivery if the decision does not require it.>

## Open Questions and Reconsideration

<Unresolved facts, confidence limits and evidence that would change the decision.
Do not present an open question as an already accepted choice.>

## Evidence and Related Decisions

| Evidence | Relevance |
| --- | --- |
| <Verified project/file/interface deep link> | <Claim or integration boundary it establishes> |
| <Official version-relevant platform documentation> | <Behavior or constraint> |
| <Related/superseded ADR, if any> | <Decision relationship> |
```

When the decision changes after acceptance, create a new record with a clear supersedes/superseded-by
relationship rather than replacing the historical rationale. Add decision-owner/acceptance dates
only when known. Keep issue open/closed state separate from ADR status.
