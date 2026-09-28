---
description: 'Always-on GitHub invariants for branch naming, remote operations, cross-visibility references, merge gates and release tags.'
applyTo: '**'
---

# GitHub

Invariants for running a repository on GitHub. Use the `github-issues-and-pull-requests` skill to
create, update, review or merge issues and pull requests, and the `repository-baseline` skill for
repository settings, required checks and SonarQube setup. How the agent works day to day belongs in
`workflow.instructions.md`.

## Branch Naming

- Before creating a branch, refresh remote branch references when a remote is available, then inspect
  the 10 most recently updated local and remote branch names. Exclude the default branch, symbolic
  remote references and every `dependabot/*` branch. Infer the repository's current naming
  convention from that evidence rather than imposing a fleet-wide suffix.
- Resolve the authenticated GitHub username dynamically; never hardcode it. Branch names use the
  form `<github_username>/yyyy-MM-<suffix>`.
- Preserve a clear recent repository pattern. This includes numbered monthly working branches such
  as `<github_username>/yyyy-MM-updates1`, `<github_username>/yyyy-MM-updates2` and
  `<github_username>/yyyy-MM-updates3`; when that sequence is current, create the next unused number.
- When the recent branches do not establish another clear convention, use concise lowercase
  kebab-case wording, for example `<github_username>/2026-09-update-docs`.

## Remote Operations

- Review pull requests locally in the current editor session or with a local subagent. Never request
  GitHub Copilot code review, invoke a cloud coding agent or start another remote review workflow
  unless the user explicitly requests that remote operation. A general request to review, publish or
  merge a pull request is not authorization to consume remote runner minutes.
- Link a pull request to an issue only when both repositories have the same visibility: public to
  public, or private to private. Never link or identify an issue across the public/private boundary
  in either direction.
- Never merge a pull request while a required status check or the SonarQube Quality Gate is absent,
  pending or failing on its current head.

## Releases

- Publish every release as an immutable tag. Never move, delete or rewrite a tag that has been published.
- **GitHub Action repositories are the only repositories that use a `v` prefix, and the only ones that use a floating tag.** They publish `vMAJOR.MINOR.PATCH` and then move the floating `vMAJOR` alias to the same commit, because that is what consumers reference in `uses:`.
- **Every other repository publishes plain `X.Y.Z` tags with no prefix and no aliases** — Terraform modules, libraries, applications and infrastructure repositories alike. Consumers pin an exact version.
- Never create a floating minor, patch or pre-release alias anywhere, including in Action repositories.
- Set the release-versioning workflow inputs to match: Action repositories keep the `v` prefix and major-alias defaults; every other repository must override both.
