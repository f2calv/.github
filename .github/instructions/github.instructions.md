---
description: 'Repository-wide GitHub conventions for branches, issues, pull requests, continuous integration, dependency automation and releases.'
applyTo: '**'
---

# GitHub

Conventions for running a repository on GitHub — branches, pull requests, status checks, dependency
automation and releases. How the agent works day to day, and how code is maintained over time,
belongs in `workflow.instructions.md`.

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

## Issues

- Search existing open and closed issues before creating a new one.
- Inspect the repository's supported issue types and assign the closest native type when types are enabled: `Bug` for unexpected behavior, `Feature` for a request or new capability, and `Task` for bounded investigation or implementation work.
- When native issue types are unavailable, apply the closest canonical type label: `bug`, `enhancement` for a feature, or `task`. Create a missing canonical label only when repository label administration is in scope.
- Inspect available labels and apply every other label that accurately describes the issue. Native issue types and labels are separate metadata; setting one does not replace the other.
- Verify the issue title, body, type and labels after creation.

### Issue Quality

An issue is a durable record that outlives the conversation that produced it, so write it for
someone arriving cold months later.

- State the decision and the evidence behind it, not only the intent. Record measured figures with
  the conditions they were measured under, and mark any figure that is approximate or unverified as
  such rather than letting it read as fact.
- Record options that were rejected and why. The reasoning is the part that cannot be recovered from
  the code.
- Deep-link generously. Link every file the work created or changed, the upstream projects and
  vendor documentation it depends on, and any related issues. Prefer a table of links over prose.
- Link repository files on the default branch so the links stay valid after the branch merges; note
  in the issue when they do not resolve yet. Use a commit permalink when the exact revision matters.
- Never deep-link a private repository from a public issue, and never expose private coordinates
  through a link target. Describe the dependency generically instead.
- Keep the issue current as the work progresses. Tick the checklist, correct figures that later
  proved wrong, and say explicitly when remaining items are parked rather than leaving them
  ambiguous.

## Pull Requests

- Keep generic issue forms and the pull request template in the public account-level `.github` repository so repositories inherit one contribution workflow.
- Prefer YAML issue forms for structured bug, feature and support reports. Pull request templates remain Markdown because GitHub does not support YAML pull request forms.
- A repository-local `ISSUE_TEMPLATE` configuration suppresses inherited issue templates. Keep local templates only when repository-specific fields are necessary; do not copy generic central templates into repositories.
- When a relevant issue already exists, link it from the pull request. Do not create an issue solely to satisfy a pull-request workflow requirement.
- A public pull request must never link to or identify an issue in a private repository. Omit the issue reference and describe only the public-safe scope needed to review the change.
- Generate the pull request description from all changes in the feature branch compared with `origin/main`, not only the latest commit or uncommitted working-tree changes.
- Inspect the repository's available labels when creating a pull request and apply every label that accurately describes the change.
- Assign a new pull request to the currently authenticated GitHub user. Resolve the login dynamically from the GitHub client or API; never hardcode a username in instructions or automation.
- Verify the pull request's base branch, head branch, labels and assignee after creation.
- After creating a pull request, and again when asked to merge it, inspect the current-head GitHub
  Advanced Security/code-scanning alerts and SonarQube pull-request analysis. Resolve every open
  critical or high finding (SonarQube `BLOCKER`/`HIGH`, or the equivalent GitHub severity), plus any
  lower-severity finding that fails a required check or Quality Gate. Re-run the affected analysis
  on the unchanged head and do not treat a passing or failing result from a superseded commit as
  evidence for the current pull request.

## Continuous Integration

- Pull requests must run the repository's formatting, initialization and validation checks, and every one of them must pass without cloud credentials.
- Require `lint / lint`, `versioning / gha-release-versioning`, the repository's own validation check
  and the SonarQube Quality Gate as status checks in the default-branch ruleset. Every pull request
  must pass all four before merge.

### SonarQube

- Configure every public repository in SonarQube Cloud on the Free plan through its GitHub
  integration. Grant the SonarQube GitHub App access to all repositories, enable automatic import
  for new repositories and bulk-import existing repositories when establishing the integration.
- Use SonarQube Cloud automatic analysis where the repository is eligible. Use CI-based analysis
  where the language, project structure or required build context is not supported, and never run
  automatic and CI-based analysis together for the same SonarQube project.
- Configure every private repository against a self-hosted SonarQube Community Build instance and
  run its scanner in continuous integration.
- Add the corresponding SonarQube Quality Gate check to the default branch's required status checks
  for every public and private repository. A pull request must not merge while that check is absent,
  pending or failing.

## Dependency Automation

- Configure Dependabot for every package ecosystem the repository uses, with one entry per manifest directory or a `directories` pattern covering them all.
- Validate automated dependency updates through the same pull request checks as manually authored changes.
- Before creating or merging a pull request, inspect the repository's open Dependabot pull requests.
  Fold a pending patch or minor update into the current branch when its change is small, compatible
  with the current work and safe to validate in the same pull request; then document and close the
  superseded Dependabot pull request. Keep major migrations, documented holds, incompatible updates
  and changes needing independent risk review separate. This consolidation avoids unnecessary pull
  request and semantic-version release churn without weakening dependency validation.

## Releases

- Publish every release as an immutable tag. Never move, delete or rewrite a tag that has been published.
- **GitHub Action repositories are the only repositories that use a `v` prefix, and the only ones that use a floating tag.** They publish `vMAJOR.MINOR.PATCH` and then move the floating `vMAJOR` alias to the same commit, because that is what consumers reference in `uses:`.
- **Every other repository publishes plain `X.Y.Z` tags with no prefix and no aliases** — Terraform modules, libraries, applications and infrastructure repositories alike. Consumers pin an exact version.
- Never create a floating minor, patch or pre-release alias anywhere, including in Action repositories.
- Set the release-versioning workflow inputs to match: Action repositories keep the `v` prefix and major-alias defaults; every other repository must override both.
