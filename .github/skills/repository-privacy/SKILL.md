---
name: repository-privacy
description: 'Check that a change, a commit message, an issue, a pull request or a release note is safe to publish from a public repository. Covers the public and private boundary, scanning for personally identifiable information, placeholder conventions, and how to reference private work from public content without disclosing it. Use before committing or pushing to a public repository, before opening or commenting on a public issue or pull request, and when a public change depends on private context.'
user-invocable: true
compatibility: 'The PII scanner requires PowerShell 7 and git. Run it against the repository being checked with -RepoRoot.'
---

# Repository Privacy

## Overview

A mixed estate of public and private repositories leaks in predictable ways: a real hostname in an
example, a private repository name in a commit message, a cross-reference from a public issue to a
private one. Each looks harmless alone. Together they disclose the shape of a private system.

This skill is the check to run before anything leaves a public repository.

## Step 1 — Establish Which Side Of The Boundary You Are On

```bash
gh repo view <owner>/<repo> --json visibility,isPrivate
```

- **Public repository** — everything below applies. Assume every tracked file, commit message, issue,
  pull request, review comment, release note and workflow annotation is world-readable forever.
- **Private repository** — real identifiers may be committed where the repository genuinely needs
  them, but they must never be copied outward. A private repository's contents are still confidential
  when quoted into a public one.

The boundary is per-repository, not per-workspace. A private repository open in the same editor
window is not a licence to reference it publicly.

## Step 2 — Scan For Leaked Values

Run the scanner against the repository before committing:

```powershell
pwsh ./.scripts/Find-Pii.ps1 -RepoRoot <path-to-repo>
pwsh ./.scripts/Find-Pii.ps1 -RepoRoot <path-to-repo> -FailOnFind      # gate a commit
pwsh ./.scripts/Find-Pii.ps1 -RepoRoot <path-to-repo> -IncludeHistory  # audit past commits
```

It works two ways: it reads the repository's gitignored local configuration to learn the *real*
values and searches for those exact strings, and it applies always-on patterns for PII shapes. The
first kind of hit is decisive; the second needs judgement.

- **High-confidence hits are blocking.** This includes values seeded from local configuration and
  machine-specific user-profile paths detected without a seed.
- **Heuristic hits need review.** A mandated placeholder such as a documentation IP address or an
  example phone number will match the shape while being entirely correct. Confirm it is a placeholder
  rather than silencing the rule.
- `-IncludeHistory` is the only way to find a value that was committed and later deleted. Removing it
  from the working tree does not remove it from the history a clone carries.

## Step 3 — Check What The Scanner Cannot See

The scanner matches values. These leaks are structural, and need reading:

- **Private repository identity** — names, URLs, owner and repository coordinates, branch names,
  file paths, or anything that reveals a private repository exists.
- **Architecture and deployment detail** — internal service names, cluster topology, namespace
  layouts, deployed versions, environment identifiers.
- **Cross-references** — a public issue or pull request that links or refers to a private issue,
  including by number. Numbers leak too: "blocked by #412" invites the question, in which repository.
- **Third-party user data** — where the repository wraps an external service, its users' account
  identifiers, phone numbers, message content, file names or media metadata, including in test
  fixtures and CI output.
- **Commit messages and release notes** — as public as the code, and far easier to forget.

## Step 4 — Rewrite Rather Than Omit

Describe the relationship generically instead of dropping the context:

| Instead of | Write |
| --- | --- |
| A private repository by name | "a private GitOps repository", "an internal service" |
| "Blocked by `<private-repo>#412`" | "Blocked by an internal dependency" |
| A real tenant, subscription or object identifier | `00000000-0000-0000-0000-000000000000` |
| A real hostname or domain | `example.com` |
| A real address | A documentation-range address |
| A real account or phone number | An obviously synthetic placeholder |

Supply genuine coordinates through repository secrets, repository variables or caller-provided
inputs — never through committed text.

## Step 5 — Before Publishing

Re-read the exact text that will become public, not the change that prompted it: the title, the body,
the labels, the branch name and the commit messages being pushed. Branch names travel with a pull
request and are easy to overlook.

The repository scanner only sees Git content. Separately inspect every proposed issue, pull-request,
review, release and workflow-dispatch title or body before sending it. Replace local absolute paths
rooted in an operating-system user profile with repository-relative paths or portable placeholders.
After creating or updating public metadata, retrieve it from the remote service and verify the
published text again; do not rely on the request payload or a cached local draft.

## Notes

- A repository that has no gitignored local configuration produces no seeds, so the scan falls back to
  heuristics only. That is a weaker check, not a clean bill of health.
- A private repository does not need routine scanning, but still must not accumulate credentials.
  Secrets belong in a secret store regardless of repository visibility.
- Add `pii-report*.csv` to the scanned repository's `.gitignore`; the report contains the extracted
  values by design.
