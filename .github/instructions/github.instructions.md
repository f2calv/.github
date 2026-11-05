---
description: 'Always-on GitHub invariants: branch naming, remote operations, cross-visibility links, merge gates and method, and release tags.'
applyTo: '**'
---

# GitHub

The `github-issues-and-pull-requests` skill owns issue and pull-request procedures; the
`github-repository-baseline` skill owns repository settings, required checks and SonarQube setup.

## Branch Naming

- Name branches `<github-username>/yyyy-MM-<suffix>`, resolving the username from the authenticated
  client rather than hardcoding it.
- Infer the suffix from the repository: fetch, then read the 10 most recently updated local and
  remote branches, ignoring the default branch, symbolic refs and `dependabot/*`. Continue a current
  numbered series such as `updates1`, `updates2` with the next unused number; otherwise use concise
  lowercase kebab-case, such as `<github-username>/2026-09-update-docs`.

## Remote Operations

- An explicit request to create or edit an issue or pull request authorizes it immediately. Use a
  non-interactive tool or API, never a confirmation form in chat, and report the URL.
- Review pull requests locally or with a local subagent. Never request Copilot code review, a cloud
  coding agent or another remote workflow unless the user explicitly asks for that remote operation.
- Before pushing a branch to create or update a pull request, fetch `origin` and merge its default
  branch (resolved from the remote, usually `main` or `master`) into the feature branch; never
  rebase a pushed branch. Resolve conflicts, then rerun the validation they affect, within the
  user's build and test approvals.
- Link an issue only between repositories of the same visibility; never link or identify an issue
  across the public/private boundary.

## Merging

- Never merge while a required check is absent, pending or failing on the current head.
- Require the SonarQube Quality Gate where pull-request analysis is supported; an expected gate that
  is absent, pending or failing never passes. Where edition or visibility prevents pull-request
  analysis, record that limitation in the merge report and rely on the required checks.
- Merge with a regular merge commit only, so the individual commits stay in history; never squash or
  rebase. If merge commits are disabled or blocked, stop and ask.
- After the merge, switch the local checkout to the default branch and fast-forward it. Delete the
  local feature branch only when its commits are reachable from the updated default branch.

## Releases

- Every release is an immutable tag; never move, delete or rewrite a published one, except the
  floating Action aliases below.
- **GitHub Action repositories** alone use the `v` prefix and floating aliases: publish
  `vMAJOR.MINOR.PATCH`, then move `vMAJOR` and `vMAJOR.MINOR` to the same commit. Consumers use
  `vMAJOR`.
- **Every other repository-level release** (libraries, applications, Terraform modules,
  infrastructure) uses a plain `X.Y.Z` tag with no prefix and no aliases; consumers pin it exactly.
- **Independently versioned monorepo components** may use `<component-id>/X.Y.Z`, never with a `v`
  prefix or aliases.
- Never create a floating patch or pre-release alias. Set the release-versioning workflow inputs to
  match: rolling aliases only for Actions, and an explicit empty or `<component-id>/` tag prefix
  otherwise.
