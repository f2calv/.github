---
name: archive-repo
description: 'Retire and archive GitHub repositories safely, including final documentation, open work, security, integrations, and local cleanup - Brought to you by f2calv/.github'
argument-hint: 'repositories=owner/name,... [remove-local={true|false}]'
user-invocable: true
disable-model-invocation: true
compatibility: 'Requires git and an authenticated GitHub CLI account with repository administration permission.'
---

# Archive Repository

## Overview

Retire one or more GitHub repositories without losing unresolved work, misleading consumers, or
leaving active automation behind. Audit first, publish a final retirement notice through the normal
pull-request process, archive only repositories that pass the retirement gate, and remove local
clones only when the user explicitly requests it.

Archiving is not deletion and is not security remediation. GitHub preserves an archived repository
as read-only, including its issues, pull requests, releases, branches, comments, permissions, and
security findings. Unarchive the repository before making any later change.

## Prerequisites

- Resolve an explicit repository list. Do not infer a destructive fleet scope from a parent clone
  directory.
- Confirm the authenticated GitHub identity dynamically with `gh api user`.
- Confirm administrative access to every repository.
- Read repository-specific contribution, release, security, and workflow instructions.
- Obtain explicit user approval for:
  - archiving each remote repository;
  - closing or transferring human-authored work;
  - discarding uncommitted or unpushed local work;
  - deleting SonarQube projects, packages, releases, deployments, or local clones.
- Use the repository privacy workflow before publishing changes or comments from a public
  repository.

## Quick Start

1. Audit the requested repositories and produce an exception report.
2. Resolve open work and external-consumer risks.
3. Add and merge a final retirement notice.
4. Update repository metadata.
5. Archive and verify each repository.
6. Optionally remove verified local clones and workspace entries.

Do not combine these stages into one unchecked bulk mutation. A failure in one repository must not
hide or misreport the state of another.

## Required Workflow

### 1. Establish Scope And State

For each explicit repository:

1. Resolve its owner, name, default branch, visibility, fork status, archive status, and local path.
2. Verify the remote URL matches the intended GitHub repository.
3. Fetch and prune remote references.
4. Record the current branch, worktree status, untracked files, unpushed commits, and linked
   worktrees.
5. Stop on a repository identity mismatch. Never archive a similarly named repository by
   assumption.

Use `gh repo view <owner>/<repo> --json` and `git -C <path>` commands rather than hardcoded account
details.

### 2. Audit Open Work

Inventory these surfaces before making changes:

- open and draft pull requests, including author and head commit;
- open issues and milestones;
- active, queued, or waiting workflow runs;
- releases, packages, GitHub Pages, environments, and deployments;
- branches and tags that contain work absent from the default branch;
- repository rulesets, branch protection, webhooks, and installed integrations;
- references from maintained repositories, workflows, documentation, packages, and infrastructure.

Classify pull requests by author:

- Human-authored pull requests require individual review. Merge, transfer, or close them only with
  explicit approval.
- Dependabot and legacy `dependabot-preview[bot]` pull requests may be closed as routine retirement
  cleanup when the user authorized the retirement workflow.
- Do not close a security fix merely because its author is automated. Review its severity and
  exploitability first.

Classify issues as resolved, obsolete, transferable to a maintained successor, historical, or
security-sensitive. Transfer still-relevant work where possible. Close other issues with a concise,
respectful retirement explanation before archival makes comments read-only.

### 3. Audit Security And Analysis

Inspect:

- Dependabot alerts and security-update pull requests;
- GitHub code-scanning alerts on the proposed final head;
- secret-scanning status without printing secret values;
- SonarQube or SonarCloud project bindings, current-head analysis, and Quality Gate status.

Resolve every critical or high code-scanning or Sonar finding before merge. Also resolve any
lower-severity finding that fails a required check or Quality Gate.

For obsolete dependencies in an intentionally retired reproduction:

- do not dismiss an alert as fixed;
- do not upgrade dependencies merely to make an unsupported sample appear current;
- state clearly that the repository is unsupported and is not secure production guidance;
- preserve the alerts as historical evidence unless the user explicitly selects another accurate
  disposition.

Archiving a GitHub repository does not necessarily delete its SonarQube project. Preserve analysis
history by default. Deleting or unbinding the external project is a separate destructive action that
requires explicit approval.

### 4. Publish The Retirement Notice

Before archival, update the repository description and its root `README.md`. Preserve the existing
README rather than replacing useful historical content.

Place this notice directly after the H1:

```markdown
> [!IMPORTANT]
> This repository has been retired and is no longer maintained. It is retained for historical
> reference and should not be treated as supported or secure production guidance.
```

Add a maintained successor link when one exists. State when the successor is not a drop-in
replacement. Do not invent a replacement or expose private repository details.

When no root README exists, create a short one containing:

1. the repository name as its only H1;
2. the retirement notice;
3. one sentence describing the historical purpose;
4. a successor link when applicable.

Run the repository privacy scan and documentation lint configured by the repository. Documentation-
only changes do not require tests unless documentation tests exist.

### 5. Create And Merge The Final Pull Request

1. Create a repository-conformant branch from the refreshed default branch.
2. Commit only the retirement documentation and directly related metadata.
3. Push the branch and open a non-draft pull request against the default branch.
4. Apply every accurate existing label and assign the authenticated user.
5. Verify the base, head, labels, assignee, and exact diff.
6. Inspect current-head GitHub code scanning and SonarQube analysis.
7. Wait for required checks and the Quality Gate to complete.
8. Merge only when the pull request is mergeable and every required check passes.
9. Verify the retirement notice exists on the remote default branch.

Do not bypass branch protection or use administrator merge privileges merely to accelerate
retirement.

### 6. Archive And Verify

Immediately before archival, verify:

- no open pull requests remain;
- no unresolved issue requires transfer or a final comment;
- no workflow run is active, queued, waiting, requested, or pending;
- the final pull request is merged into the current default branch;
- the retirement notice and repository description are present;
- releases and packages that consumers may still download are intentionally preserved;
- known external consumers and successor documentation have been considered.

Archive with the GitHub API only after every gate passes:

```bash
gh api --method PATCH repos/<owner>/<repo> -F archived=true
```

Read the repository again and require `archived: true`. Report partial success per repository rather
than presenting a fleet operation as successful when any item failed.

### 7. Optional Local Cleanup

Remote archival does not authorize local deletion.

When the user explicitly requests local cleanup:

1. Verify the remote repository reports `archived: true`.
2. Verify the clone contains no uncommitted files, untracked files, or unpushed commits.
3. Ask before discarding any unexpected work.
4. Remove the exact repository entry from every applicable `.code-workspace` file.
5. Parse each edited workspace file before deleting anything.
6. Resolve and validate each exact clone path beneath the approved parent directory.
7. Delete only the named clone. Never use a wildcard or recursively delete the workspace root.
8. Verify the path is absent and the workspace contains no stale reference.

## Stop Conditions

Stop the affected repository and report it when:

- identity or administrative access cannot be proven;
- human-authored work lacks a disposition;
- unpushed or unexpected local work exists;
- a critical or high current-head security finding remains;
- a required check or Quality Gate fails or is pending;
- a workflow or deployment is active;
- an external consumer would be broken without an agreed migration;
- the final retirement notice is absent from the default branch;
- archival or post-archive verification fails.

Continue processing independent repositories only when doing so cannot obscure the failure.

## Reporting

Report:

- repositories requested, archived, skipped, and failed;
- issues and pull requests closed, transferred, merged, or left open;
- unresolved Dependabot and code-scanning alerts by severity;
- SonarQube status and whether external project history was preserved;
- releases, packages, Pages, and deployments intentionally retained;
- final pull-request links and merge commits;
- repository descriptions updated;
- local workspace entries and clone paths removed;
- validation performed and any checks not run.

Never report an archived repository as deleted. Never report an alert as resolved when it was only
made read-only by archival.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Repository becomes read-only too early | Unarchive it, complete the pending changes and comments, then repeat the gate. |
| Dependabot PR is mistaken for human work | Recognize both `dependabot[bot]` and legacy `dependabot-preview[bot]`. |
| Sonar API access is unavailable | Use current-head GitHub checks and imported code-scanning results; preserve the external project and report the limitation. |
| A generated file changes during commit | Inspect it, exclude it from the retirement commit, and ask before discarding it. |
| A local clone cannot be deleted | Check linked worktrees and processes using the directory; do not broaden the deletion command. |
| Only some repositories archive | Verify each result independently and report exact failures before retrying. |

## References

- [Archiving repositories](https://docs.github.com/en/repositories/archiving-a-github-repository/archiving-repositories)
- [Dependabot alerts](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-alerts)
- [About code scanning](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning)

> Brought to you by f2calv/.github
