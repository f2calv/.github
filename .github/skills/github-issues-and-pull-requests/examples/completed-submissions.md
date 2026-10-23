# Completed Issue and Pull Request Examples

These synthetic drafts demonstrate the existing contribution forms, not new templates or actual
submissions. No search, CI run, release or GitHub operation is claimed by the scenarios below.
Replace the scenario evidence with observed facts before publishing.

## Bug Report

The [bug draft](./bug-report.md) uses the current
[bug form](../../../ISSUE_TEMPLATE/1-bug.yml): its title prefix and field headings are kept in order.
The submission checks remain unchecked because no real duplicate search or publication review has
been performed. This is a completed **draft**, not a submission-ready claim. Do not tick a required
check merely to satisfy the form; perform the check or do not submit.

The synthetic defect has a small reproduction, expected behavior, version and environment.
The report deliberately avoids a fabricated issue number, live endpoint, stack trace or source URL.
In a real report, add verified same-visibility source links and actual evidence; distinguish an
observed defect from an unverified hypothesis about its cause.

Select the repository's supported native Bug type or its existing fallback label, and add only
other accurate available labels. Type, labels and assignee are metadata, not additional body
headings. Retrieve the created issue to verify both metadata and body.

## Pull Request Without an Issue

The [pull-request draft](./pull-request.md) retains every section and checklist statement of the
[central template](../../../pull_request_template.md). It shows a bounded documentation change:
no issue is invented, unrelated branch content is disclosed, and unexecuted checks stay unexecuted.

The example's unchecked validation-sensitive item is intentional. The checklist is not a substitute
for required current-head checks. A local pass, a prior commit's result or a skipped check must not
be described as a passing PR gate.

Generate the final body from the **entire branch diff against its resolved base**, not `origin/main`
by assumption and not just the latest commit. Preserve template section order when describing:

* the main change and any small unrelated change;
* breaking changes, migrations, or their explicit absence;
* commands actually run and checks not run, with reasons;
* pending publication/operational verification and its owner;
* folded Dependabot changes, only if any were actually folded.

The draft's follow-up belongs to the documentation owner after the updated source is published.
It does not authorize a push or merge. For larger deferred implementation work, record a durable
same-visibility issue or declaration-level TODO rather than leaving an ambiguous PR checklist.

## Validation and Publication

The regression checks compare the example headings and checklist wording with the actual forms.
That detects template drift, not factual truth. Before a real API/CLI submission, resolve the
effective local or inherited template, review identifiers and links, verify every evidence claim,
then publish only with authorization. Retrieve the published result to confirm it was accepted.
