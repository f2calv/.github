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
  - Push the branch and create or update one pull request covering the full branch diff.
  - Link an existing issue when relevant. Never create an issue solely because a pull-request
    template asks for one.
  - Apply accurate labels and assign the authenticated user.
- **Review and merge**
  - Wait for every required check on the current head SHA.
  - Resolve critical/high GitHub security and SonarQube findings, plus any lower finding that fails a
    required check or quality gate.
  - Treat missing expected build, test, or Sonar checks as a CI coverage gap, not a passing result.
  - Use a merge commit unless the repository explicitly requires another strategy. Do not squash a
    multi-commit release branch by default.
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
    - PowerShell: `./scripts/Test-NuGetPackageAvailability.ps1 -PackageId <ids> -Version <version>`.
      Invoke it in-process with `&`; `pwsh -File` binds an array of IDs positionally and fails.
    - Bash: `./scripts/test-nuget-package-availability.sh <version> <ids>`
  - If the repository publishes no packages, continue once its merge and release checks are complete.
- **Update documentation downstream**
  - In each consumer's pull request, remove README statements the release has made untrue, such as
    "Debug-only", "Release build not supported", "not yet published" or adjacent-checkout
    requirements, and add package badges or version rows for packages that now exist.
  - Search for them before opening the pull request rather than relying on memory, for example
    `Debug[- ]only|Release (build|graph)|not (yet )?(published|released)|adjacent (checkout|clone)`.

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
