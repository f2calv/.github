---
description: 'Repository-wide forward-only maintenance, branch, pull request and continuous integration conventions.'
applyTo: '**'
---

# GitHub

Conventions for running a repository on GitHub — branches, pull requests, status checks, dependency
automation and releases. How the agent works day to day, and how code is maintained over time,
belongs in `workflow.instructions.md`.

## Branch Naming

- Name feature branches `<github_username>/yyyy-MM-concise-name`, for example `<github_username>/2026-09-update-docs`.
- Use the branch creation year and month, followed by concise lowercase kebab-case wording.

## Pull Requests

- Inspect the repository's available labels when creating a pull request and apply every label that accurately describes the change.
- Assign a new pull request to the currently authenticated GitHub user. Resolve the login dynamically from the GitHub client or API; never hardcode a username in instructions or automation.
- Verify the pull request's base branch, head branch, labels and assignee after creation.

## Continuous Integration

- Pull requests must run the repository's formatting, initialization and validation checks, and every one of them must pass without cloud credentials.
- Require `lint / lint` and `versioning / gha-release-versioning`, together with the repository's own validation check, as status checks in the `main` branch ruleset.

## Dependency Automation

- Configure Dependabot for every package ecosystem the repository uses, with one entry per manifest directory or a `directories` pattern covering them all.
- Validate automated dependency updates through the same pull request checks as manually authored changes.

## Releases

- Publish every release as an immutable tag. Never move, delete or rewrite a tag that has been published.
- **GitHub Action repositories are the only repositories that use a `v` prefix, and the only ones that use a floating tag.** They publish `vMAJOR.MINOR.PATCH` and then move the floating `vMAJOR` alias to the same commit, because that is what consumers reference in `uses:`.
- **Every other repository publishes plain `X.Y.Z` tags with no prefix and no aliases** — Terraform modules, libraries, applications and infrastructure repositories alike. Consumers pin an exact version.
- Never create a floating minor, patch or pre-release alias anywhere, including in Action repositories.
- Set the release-versioning workflow inputs to match: Action repositories keep the `v` prefix and major-alias defaults; every other repository must override both.
