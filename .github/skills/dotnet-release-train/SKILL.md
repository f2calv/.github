---
name: dotnet-release-train
description: 'Update, validate, release, and propagate NuGet packages through dependent .NET repositories. Use for routine dependency sweeps and chained releases beginning with CasCap.Common.'
argument-hint: '[start=CasCap.Common] [packages={all|internal}]'
user-invocable: true
---

# .NET Release Train

Move through dependent .NET repositories in package order. Finish and publish each producer before
updating its consumers. Use the repositories' existing branches, workflows, package holds, and
release conventions rather than maintaining a separate release state machine.

## Repository Order

- **CasCap.Common** — always start here when its packages need updating.
  - Update external packages and the shared source.
  - Validate every packable `CasCap.Common.*` project.
  - Merge and release it.
  - Wait until every package from the release is restorable from NuGet.
- **Direct CasCap.Common consumers** — continue only after the Common packages are available.
  - `CasCap.Api.Azure`
    - Update every consumed `CasCap.Common.*` package together.
    - Release its `CasCap.Api.Azure.*` packages and wait for all of them on NuGet.
  - `CasCap.Api.SignalCli`
    - Update every consumed `CasCap.Common.*` package together.
    - Release `CasCap.Api.SignalCli` and wait for it on NuGet.
  - `CasCap.Api.GooglePhotos`
    - Update its Common packages.
    - Release `CasCap.Api.GooglePhotos` and wait for it on NuGet.
  - `yamlizr`
    - Update its Common packages and other dependencies.
    - Release through its existing global-tool workflow.
- **Voice API** — continue only after the CasCap.Api.Azure packages are available.
  - `CasCap.Api.Voice`
    - Update every consumed `CasCap.Common.*` and `CasCap.Api.Azure.*` package together.
    - Release `CasCap.Api.Voice` and wait for the exact version on NuGet.
- **CasCap.GooglePhotosCli** — continue after `CasCap.Api.GooglePhotos` is available.
  - Update `CasCap.Api.GooglePhotos`.
  - Validate and release the CLI through its existing global-tool workflow.
- **Application repositories** — do these last, after every package they consume is available.
  - Update all newly released internal packages together.
  - Validate the complete application rather than publishing another NuGet package unless that
    repository explicitly produces one.
  - Process public applications such as SmartHaus and any private application consumers discovered
    in the current workspace. Never publish private repository names or topology from this public
    skill.

Repositories at the same indentation level do not depend on one another. Process them sequentially
unless the user explicitly asks for parallel sessions.

## Repeat For Each Repository

- **Inspect**
  - Read the repository instructions and documented package holds first.
  - Fetch the default branch and inspect the current branch, worktree, existing pull request, and
    open Dependabot pull requests.
  - Preserve unrelated work. Do not create another branch or pull request when the current one is
    already the correct release branch.
  - Fold in a small compatible patch or minor Dependabot update when it can be validated in the same
    pull request. Keep major migrations and documented holds separate.
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
  - Merge only after the user authorizes it or an active auto-merge instruction covers it.
- **Verify the release**
  - Switch the local checkout to the default branch, fast-forward from origin, and delete the merged
    local branch when no other worktree owns it.
  - Wait for default-branch CI and the immutable GitHub release tag.
  - Derive the released version from the tag; do not infer it from GitVersion output or a pull-request
    prerelease version.
  - If the repository publishes NuGet packages, verify every expected package ID at that exact
    version before continuing downstream.
    - PowerShell: `./scripts/Test-NuGetPackageAvailability.ps1 -PackageId <ids> -Version <version>`
    - Bash: `./scripts/test-nuget-package-availability.sh <version> <ids>`
  - If the repository publishes no packages, continue once its merge and release checks are complete.

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
- A successful package push is not proof that NuGet clients can restore it.
- Keep each repository's package holds in its own instructions; do not duplicate them here.
- Do not mix deployment or live-cluster debugging into the release train unless the user asks for it.
- Keep status updates short: current repository, latest verified package version, blocker, next
  repository.
