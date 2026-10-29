---
name: github-issues-and-pull-requests
description: 'Create, update, review, and merge GitHub issues and pull requests: issue types, labels and quality, pull request descriptions from the full branch diff, assignees, Dependabot folding, code-scanning and SonarQube gates, and merge readiness.'
argument-hint: 'mode={issue|pr-create|pr-update|pr-merge} [repository=owner/name]'
user-invocable: true
---

# GitHub Issues and Pull Requests

Run the issue and pull-request lifecycle consistently. The always-on GitHub instructions own branch
naming, the local-review default, cross-visibility linking and release tags; the workflow
instructions own commit, push and merge-method switches. This skill does not grant extra Git or
GitHub permission.

## Prerequisites

- Resolve the repository, its visibility and the authenticated GitHub login dynamically; never
  hardcode a username.
- For a public repository, apply the `repository-privacy` skill before publishing any title, body,
  label, comment or review.

## Issues

1. Search existing open and closed issues before creating a new one.
2. Fill the matching issue form (see [Templates](#templates)).
3. Inspect the repository's supported issue types. When types are enabled, assign the closest native
   type: `Bug` for unexpected behavior, `Feature` for a request or new capability, and `Task` for
   bounded investigation or implementation work.
4. When native types are unavailable, apply the closest canonical type label: `bug`, `enhancement`
   for a feature, or `task`. Create a missing canonical label only when label administration is in
   scope.
5. Inspect available labels and apply every other label that accurately describes the issue. Native
   types and labels are separate metadata; setting one does not replace the other.
6. Verify the title, body, type and labels after creation.

### Issue Quality

An issue is a durable record that outlives the conversation that produced it, so write it for
someone arriving cold months later.

- State the decision and the evidence behind it, not only the intent. Record measured figures with
  their conditions, and mark approximate or unverified figures as such.
- Record rejected options and why; that reasoning cannot be recovered from the code.
- Deep-link generously: every file the work created or changed, upstream projects, vendor
  documentation and related issues. Prefer a table of links over prose.
- Link repository files on the default branch so links survive the merge, and note when they do not
  resolve yet. Use a commit permalink when the exact revision matters.
- Never deep-link a private repository from a public issue or expose private coordinates through a
  link target; describe the dependency generically.
- Keep the issue current: tick the checklist, correct figures that proved wrong, and say explicitly
  when remaining items are parked.

## Templates

See the [completed submission guide](./examples/completed-submissions.md),
[bug draft](./examples/bug-report.md) and [PR draft](./examples/pull-request.md) for form-aligned
examples with explicit evidence and unchecked publication gates. They are not real submissions.

- Keep generic issue forms and the pull request template in the public account-level `.github`
  repository so repositories inherit one contribution workflow.
- Prefer YAML issue forms for structured bug, feature and support reports. Pull request templates
  remain Markdown because GitHub does not support YAML pull request forms.
- A repository-local `ISSUE_TEMPLATE` configuration suppresses inherited templates. Keep local
  templates only for repository-specific fields; never copy the central templates.
- Creating an issue or pull request through `gh` or the API bypasses the web forms, so fill the
  template yourself. Resolve the effective template, a repository-local one first and then the
  account-level `.github` one.
  - Issues: use the matching form's `title` prefix and write one `###` section per field `label`, in
    form order. Leave an optional field out only when it has nothing to say; answer submission
    checks truthfully, and skip the issue rather than tick a false one.
  - Pull requests: keep every `##` section of `pull_request_template.md` in order and tick only the
    checklist items that are true. Put validation, compatibility notes and Dependabot folding under
    the template's sections rather than adding parallel headings.

## Create a Pull Request

1. Inspect open Dependabot pull requests. Fold a pending patch or minor update into the branch when
   it is small, compatible and safe to validate in the same pull request, then document and close the
   superseded Dependabot pull request. Keep major migrations, documented holds, incompatible updates
   and changes needing independent risk review separate.
2. Generate the title and description from every change in the branch compared with its resolved base,
   not only the latest commit or the working tree, filling the pull-request template (see
   [Templates](#templates)). Include validation, compatibility notes and operational follow-up, and
   mention small unrelated tweaks carried on the branch.
3. Link an existing relevant issue with the same visibility. Never create an issue solely to satisfy
   a pull-request template; write "None" and the reason under Related Issue instead.
4. Apply every accurate label from the repository's available labels and assign the authenticated
   user.
5. Verify the base branch, head branch, labels and assignee after creation.

## Update a Pull Request

After pushing more commits to a branch with an open pull request, regenerate the title and
description from the complete branch diff against its base. Add every new scope, validation result,
compatibility note and follow-up, and remove claims made obsolete by later commits.

## Security and Quality Gates

After creating a pull request, and again before merging it:

1. Inspect the current-head GitHub Advanced Security and code-scanning alerts and the SonarQube
   pull-request analysis. Tools may report against `refs/pull/<n>/merge` or `refs/pull/<n>/head`.
   Inspect alert instances and correlate their refs and commit SHAs with the current pull request;
   an empty query for one ref is not evidence that no findings exist. A code-scanning annotation also
   opens a review thread, which blocks merge when the ruleset requires resolved threads.
2. Resolve every open critical or high finding (SonarQube `BLOCKER`/`HIGH`, or the equivalent GitHub
   severity), plus any lower-severity finding that fails a required check or Quality Gate.
   For a verified false positive, record a code-specific rationale within GitHub's 280-character
   dismissal-comment limit and resolve only the matching review thread. Verify the source tool's
   disposition as well as its GitHub mirror; synchronization is not proof that the Quality Gate has
   been recalculated.
3. Re-run affected analysis on the unchanged head. A result from a superseded commit is not evidence
   for the current pull request.
4. Treat a missing expected build, test or SonarQube check as a coverage gap, not a pass. Apply the
   [GitHub merge gates and analysis-capability boundary](../../instructions/github.instructions.md):
   require current-head checks and supported PR analysis; report an edition/visibility limitation
   explicitly rather than treating unavailable analysis as either a passing gate or an executable check.

## Merge

1. Re-check Dependabot folding, the security and quality gates, and every required check on the
   current head.
2. Merge only with the user's authorization, using the merge method and local synchronization rules
   in the workflow instructions.
3. Verify the merge commit on the default branch and any release tag the default-branch CI produces.

## Reporting

Report the issue or pull request URL, applied type, labels and assignee, gate results on the
current head, folded or closed Dependabot pull requests, and any check still pending or not run.

## Maintaining This Skill

- `gh` and GitHub API commands, including which refs code scanning and checks report against.
- Ruleset behaviours that block merges, such as required review threads and up-to-date branches.
- Issue types, labels and description conventions.
- Keep example headings and checklist wording aligned with the effective forms; never promote
  synthetic evidence or unchecked submission requirements into claims about a real issue or PR.
