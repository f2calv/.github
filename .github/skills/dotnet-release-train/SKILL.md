---
name: dotnet-release-train
description: 'Update, validate, release, and propagate NuGet packages through dependent .NET repositories. Use for routine dependency sweeps and chained releases: CI tooling and Helm charts first, then the base library and its consumers in dependency order.'
argument-hint: '[start={tooling|<first-producer>}] [packages={all|internal}]'
user-invocable: true
---

# .NET Release Train

Move through dependent .NET repositories in package order. Finish and publish each producer before
updating its consumers. Use the repositories' existing branches, workflows, package holds, and
release conventions rather than maintaining a separate release state machine.

## Repository Order

The [producer/consumer worked example](./examples/producer-consumer.md) connects Debug project
references, Release package references, a local partial-publication failure and the existing
availability gate. It is a synthetic laboratory, not permission to publish or start a train.

Build the order from the actual package graph: a repository moves only after every package it
consumes is published. The waves below are the general shape; the
[real-world example](#real-world-example-f2calv-net-release-train) shows one concrete train.

- **Tooling wave** — release first whenever these repositories have unreleased commits, because every
  later pull request runs on them.
  - GitHub Action repositories, in dependency order: an Action consumed by another Action or by a
    reusable workflow is released before its consumer.
    - Consumers pin floating majors (`@v1`, `@v2`), so a release takes effect fleet-wide when the
      alias moves. Confirm that pending commits are non-breaking for that major; a breaking change
      needs a new major and consumer updates instead.
  - Helm chart repositories. Release a shared chart before any chart that bundles it, and bump the
    bundled dependency in the same pull request. After publication, update every GitOps pin that
    references the chart directly. Application charts that bundle it move in their own
    repository's wave.
  - The customization repository is merged **last of the whole train**, so lessons learned while
    running the train land in its skills and instructions within the same pull request.
- **Base library** — the shared library every other package builds on, whenever its packages need
  updating.
  - Update external packages and the shared source.
  - Validate every packable project.
  - Merge and release it.
  - Wait until every package from the release is restorable from NuGet.
- **Direct consumers** — libraries and tools that depend only on the base library.
- **Second-level libraries** — packages that consume a direct consumer, such as a domain API built on
  a shared cloud-integration library.
- **Platform packages** — contracts and clients published by service repositories, in their own
  dependency order.
- **Application repositories** — do these last, after every package they consume is available.
  - Update all newly released internal packages together.
  - Validate the complete application rather than publishing another NuGet package unless that
    repository explicitly produces one.
  - Include private application consumers discovered in the current workspace, but never publish
    private repository names or topology in a public skill, issue or pull request.

Repositories at the same level do not depend on one another. Process them sequentially unless the
user explicitly asks for parallel sessions.

## Repeat For Each Repository

- **Inspect**
  - Read the repository instructions and documented package holds first.
  - Fetch the default branch and inspect the current branch, worktree, existing pull request, and
    open Dependabot pull requests.
  - Before releasing a producer, confirm every consumer's Release graph is complete: a reference
    that exists only as a Debug `ProjectReference`, with no Release `PackageReference`, blocks the
    consumer's Release build after the producer ships. Fix the graph on the consumer's branch
    before releasing the producer.
  - Preserve unrelated work. Do not create another branch or pull request when the current one is
    already the correct release branch.
  - Fold in a small compatible patch or minor Dependabot update when it can be validated in the same
    pull request. Keep major migrations and documented holds separate.
  - For a repository's first package release, confirm that CI actually publishes. An application
    repository may only build and test, so add a default-branch `package` job using the shared NuGet
    publish action, mirroring an existing app-plus-package repository, and gate `release` on it. Ask
    the user to create the nuget.org Trusted Publishing policy (owner, repository, `ci.yml`) before
    merging. Replace "no NuGet listing" README caveats with install commands and badges in the same
    pull request.
- **Update packages**
  - Update all active stable versions in `Directory.Packages.props`, not only internal packages,
    unless the user requests `packages=internal`.
  - Preserve conditions, exact holds, and major ceilings from repository instructions.
  - Keep package families aligned where they share a release line.
  - Update an internal package only to a version already verified on NuGet. Never predict the next
    version and use that prediction downstream.
- **Validate locally**
  - Ask once for authorization to run the train's builds and tests; do not ask again for every
    repository while that scope remains unchanged.
  - Restore and build the repository's Debug solution when it uses local `ProjectReference` paths.
  - Restore and build its Release solution to prove the published `PackageReference` path.
  - Run the repository's lint command and all relevant unit tests.
  - Run integration tests when authorized and their dependencies are available.
    - Classify failures caused by unavailable external services, credentials, market hours, or local
      infrastructure separately from code regressions.
    - Do not expand the release into speculative repairs for retired or offline providers. Record a
      durable skip/TODO when the test can no longer run.
  - Fix build, analyzer, packaging, and deterministic test failures before continuing.
- **Commit and open the pull request**
  - Follow the normal auto-commit and auto-push switches; the skill grants no extra Git permission.
  - For public repositories, run the privacy scan before committing.
  - Use conventional commits and keep unrelated changes separate.
  - Before every authorized push, automatically perform the
    [unpushed attribution cleanup](#unpushed-attribution-cleanup), including on resume and after
    adding commits. Do not wait for a separate cleanup request.
  - Push the branch and create or update one pull request covering the full branch diff.
  - Link an existing issue when relevant. Never create an issue solely because a pull-request
    template asks for one.
  - Apply accurate labels and assign the authenticated user.
- **Review and merge**
  - For a large or breaking pull request, complete the
    [release-version decision](#release-version-decision) before merging, even when auto-merge is
    enabled. Do not silently accept the default patch increment.
  - Wait for every required check on the current head SHA.
  - Resolve critical/high GitHub security and SonarQube findings, plus any lower finding that fails a
    required check or quality gate.
  - Treat missing expected build, test, or Sonar checks as a CI coverage gap, not a passing result.
  - Use the merge method and blocked-merge procedure in the shared workflow instructions; do not
    silently switch to squash or rebase when regular merge is unavailable.
  - When a ruleset requires branches to be up to date and the pull request is behind, update it with
    `gh pr update-branch`, which merges the base server-side, then wait for the checks on the new
    head. Never rebase or force-push a published release branch for this.
  - Merge only after the user authorizes it or an active auto-merge instruction covers it.
- **Verify the release**
  - Switch the local checkout to the default branch, fast-forward from origin, and delete the merged
    local branch when no other worktree owns it.
  - Wait for default-branch CI and the immutable GitHub release tag. Select the run by the merge
    commit SHA (`gh run list --commit <sha>`), not by the latest run on the branch, which may still
    be the previous push.
  - For an Action repository, confirm the floating major tag now dereferences to the release commit
    (`git ls-remote --tags origin 'v1^{}'`).
  - Derive the released version from the tag; do not infer it from GitVersion output or a pull-request
    prerelease version.
  - If the repository publishes NuGet packages, verify every expected package ID at that exact
    version before continuing downstream.
    - From this skill's directory, PowerShell:
      `./scripts/Test-NuGetPackageAvailability.ps1 -PackageId <ids> -Version <version>`.
      Invoke it in-process with `&`; `pwsh -File` binds an array of IDs positionally and fails.
    - Bash: `./scripts/test-nuget-package-availability.sh <version> <ids>`
  - If the repository publishes no packages, continue once its merge and release checks are complete.
- **Update documentation downstream**
  - In each consumer's pull request, remove README statements the release has made untrue, such as
    "Debug-only", "Release build not supported", "not yet published" or adjacent-checkout
    requirements, and add package badges or version rows for packages that now exist.
  - Search for them before opening the pull request rather than relying on memory, for example
    `Debug[- ]only|Release (build|graph)|not (yet )?(published|released)|adjacent (checkout|clone)`.

## Release-Version Decision

- Review the full branch diff and commits for consumer impact, not only the pull-request title.
  Prompt for a substantial feature, architectural migration, or broad refactor, and always for
  removed or renamed public contracts, incompatible configuration, or other breaking behaviour.
  Diff size alone does not determine a semantic version.
- Inspect the repository's `GitVersion.yml`, release workflow and scoped versioning instructions,
  the latest immutable release tag, and any existing version directives on the branch. Do not
  assume that conventional-commit wording or `BREAKING CHANGE` automatically controls GitVersion.
- Before merging, use a UI choice to ask whether to deliberately bump **major**, bump **minor**, or
  retain the **patch/default increment**. Show the current version, expected outcome of each
  choice, and relevant compatibility impact. Recommend major for breaking changes, minor for
  compatible new functionality, and patch for compatible fixes or internal-only refactoring.
  For pre-1.0 packages, explain the repository's established breaking-change policy.
- Wait for an explicit decision for that pull request; general merge approval or an active
  auto-merge instruction does not select a version. Reconfirm if subsequent changes materially
  alter the compatibility assessment.
- Apply the selected increment using the repository's established mechanism. When it uses
  `+semver:` commit directives, inspect every commit since the merge base, reuse or correct the
  existing directive rather than stacking conflicting requests, and verify which directive maps
  to the chosen increment under that repository's configuration. Do not hardcode a directive
  mapping or change the global increment policy to release one pull request.
- Preserve published history: use a normal authorized follow-up commit or the supported
  release-workflow input instead of amending or force-pushing published commits. If an existing
  directive prevents the selected result without rewriting history, stop and ask for direction.
- Verify the resulting numeric version with the repository's GitVersion configuration and release
  path; do not mistake a pull-request prerelease version for the eventual release. Record the
  selected increment and rationale in the pull request, update affected consumer examples or
  major-tag references, and wait for required checks on the final head before merging. If the
  requested result cannot be verified, stop rather than silently falling back to patch.
- Keep the post-merge immutable-tag and package-availability checks: the version decision is not
  proof that the intended release was published.

## Unpushed Attribution Cleanup

- Refresh every configured remote before identifying candidates. Stop if a fetch fails.
- Inspect commits reachable from the release branch but not from any remote branch or published
  tag, not just `@{u}..HEAD`; a commit already published on another ref must remain unchanged.
- Remove every `Co-authored-by:` trailer, case-insensitively, from those unpushed commits,
  regardless of the named co-author. Leave the rest of each message unchanged except for the
  trailing blank lines left by removal. If none match, make no changes.
- Rewrite affected commits and their unpushed descendants, preserving trees, author and committer
  identities and timestamps, merge topology, and all other commit metadata. Do not rebase or replay
  patches. Stop for signed commits or signature-bearing metadata that cannot remain valid.
- Keep local recovery refs to the original branch tips. Update branch refs with expected-old-SHA
  guards; preserve the index, working-tree edits, untracked files and active checkout. Do not move a
  branch checked out in another worktree or rewrite the default branch.
- Verify every rewritten tree and metadata field, confirm that only the trailers and necessary
  parent IDs changed, and rescan the candidate range for remaining attribution. Surface failures
  and stop before pushing; do not silently skip a failed cleanup.
- This step authorizes only local unpushed attribution rewrites within the train's repositories,
  not a workspace-wide sweep, a push, a timestamp change or a published-history rewrite.
  Follow the shared privacy and timestamp checks. Never force-push merely for this cleanup; if
  published attribution is found, report it and request separate authorization to rewrite it.
- Report the repositories and footer counts cleaned, or state that none were found.

## Interruptions And Resume

- Do not maintain a checkpoint schema, stage names, plan fingerprints, or a parallel source of truth.
- When interrupted, report only:
  - the last repository merged and released;
  - the package IDs and versions confirmed on NuGet;
  - the repository currently being updated;
  - the next direct consumer.
- On resume, inspect Git, GitHub, releases, and NuGet again. Trust current remote evidence rather than
  stale notes from the earlier session.
- Stop the chain when an upstream package is not published, a required check fails, a merge conflict
  needs judgment, or the user changes scope. Continue from that repository after the blocker is
  resolved.

## Practical Rules

- Package publication, not merge completion, unlocks the next consumer.
- Release builds matter even when Debug builds pass, because Debug commonly uses local project
  references while Release consumes NuGet packages.
- A successful package push is not proof that NuGet clients can restore it. Verify every expected
  package ID at the exact version through the package source's restore endpoint, and stop the chain
  when any package from a multi-package producer is absent.
- The availability helpers support public nuget.org only; authenticated feeds need a separate
  credential-safe implementation. Never put a NuGet API key in source, configuration or logs.
- Use `--skip-duplicate` only to make an idempotent publication retry safe; it never permits
  rebuilding or replacing an immutable published version.
- Keep each repository's package holds in its own instructions; do not duplicate them here.
- Do not mix deployment or live-cluster debugging into the release train unless the user asks for it.
- Keep status updates short: current repository, latest verified package version, blocker, next
  repository.

## Real-World Example: f2calv .NET Release Train

The public f2calv repositories release in this order. Indented repositories within a wave do not
depend on one another.

- **Tooling wave**
  - Actions: `gha-release-versioning` and `gha-dotnet-nuget` (the NuGet publish action) before the
    `gha-workflows` reusable workflows that consume them.
  - Charts: `helm-charts`, whose `workload` chart is bundled by every application chart.
  - `.github`, merged last of the whole train.
- **Base library**: `CasCap.Common` and its `CasCap.Common.*` packages.
- **Direct consumers**, each updating every consumed `CasCap.Common.*` package together:
  - `CasCap.Api.Azure`, releasing all `CasCap.Api.Azure.*` packages.
  - `CasCap.Api.SignalCli`.
  - `CasCap.Api.GooglePhotos`.
  - `yamlizr`, released through its global-tool workflow.
- **Second-level libraries**:
  - `CasCap.Api.Voice`, after `CasCap.Api.Azure`.
  - `CasCap.GooglePhotosCli`, after `CasCap.Api.GooglePhotos`, through its global-tool workflow.
- **Platform packages**:
  - `agentizr` releases the Agent Runtime contracts and client; its host ships as an image and chart.
  - `signalizr` releases its client, Comms and Comms AI packages together, after the Agent Runtime
    packages are on NuGet.
- **Applications**: `SmartHaus` and `tutorizr`, plus private application consumers in the workspace.

## Maintaining This Skill

- Repository order and package levels when a repository gains, loses or moves packages, in both the
  generic waves and the real-world example.
- Release-run, tag and NuGet verification commands, and the ruleset behaviours that block merges.
- Downstream README caveats to remove once the release they wait for lands.
- Keep the worked example's reference conditions, central package versions and availability-helper
  invocation aligned; validate with isolated local feeds without querying synthetic IDs remotely.
