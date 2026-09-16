---
description: 'Repository-wide forward-only maintenance, branch, pull request and continuous integration conventions.'
applyTo: '**'
---

# GitHub

## Forward-Only Maintenance

- Maintain only current supported behavior. Remove deprecated, retired, legacy and no-op code instead of preserving compatibility aliases or shims.
- Prefer a clean versioned release over compatibility code. Consumers remain on an older immutable tag until they are ready to migrate.
- Remove commented-out implementations and speculative placeholders. Git retains history.

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
