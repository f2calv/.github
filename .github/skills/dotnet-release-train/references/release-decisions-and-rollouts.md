# Release Decisions and Workload Rollouts

How the train chooses each release version and rolls released workloads out to Kubernetes.

## Release Documentation

- Before opening the pull request, compare the root README and every packable project's README
  with the branch diff and the evaluated list of packable projects.
- Every published package needs a package table row or badge, and a short description with an
  install command. Add rows for new packages; remove rows for retired ones.
- Describe new features, configuration options and breaking changes where the README covers that
  area. For a major release, add migration notes or link to them.
- Check version numbers, target frameworks, examples and API names against the code being released.
- Fix stale content in the release pull request itself, or record it in the pull request
  description with a follow-up when it is too large for this release. Use the
  [README skill](../../docs-readme/SKILL.md) for structure and wording.
- In each consumer's pull request, remove README statements the release has made untrue, such as
  "Debug-only", "Release build not supported", "not yet published" or adjacent-checkout
  requirements, and add package badges or version rows for packages that now exist.
- Search for them before opening the pull request rather than relying on memory, for example
  `Debug[- ]only|Release (build|graph)|not (yet )?(published|released)|adjacent (checkout|clone)`.

## Clean-SemVer Workload Rollouts

Development deployments through `deploy.ps1` may still be running Debug images after a successful
pull-request merge and release. After verifying a .NET Kubernetes application's release, use a UI
question: "Do you wish to roll out a new version of `<application>` (`<released X.Y.Z>`) from the GitHub
workflows?" Offer rollout now, defer to the next agreed batch, hold until the end of the train, or
decline this rollout. Respect existing publication and deployment holds.

- Let the user choose end-of-train rollouts or batches at useful milestones. Keep deferred
  applications and their verified versions in the existing task list, not a separate release state
  machine, and revisit them at the selected milestone and before the final report.
- Obtain explicit dispatch approval for the named application/version/environment, individually or
  as a clearly identified batch. Deferral is not approval to dispatch later; confirm the pending
  batch when it is due. Merge, release, auto-push and prior Debug-deployment permissions do not
  authorize these workflow runs.
- Inspect the repository's existing GitHub deployment workflow and declared inputs. Use its
  release path to build or select the published Release artifact with a clean `X.Y.Z` version,
  such as `1.2.3`, tied to the verified release commit. Do not invent workflow inputs, substitute
  `latest-dev` or a prerelease, merely retag a Debug image, or rerun `deploy.ps1` instead.
- Follow the dispatched run through build, publication and deployment. Verify the exact released
  artifact and actual workload rollout using the
  [container deployment verification guidance](../../containers-workflows/examples/caller-setup.md#check-the-result);
  a successful merge, tag or workflow dispatch alone is insufficient. Report the workflow URL,
  deployed version and verification result.
- Treat workflow failures as blockers for the affected rollout and investigate them while the
  train is in progress. Fix introduced CI/build/deployment bugs through the normal validation,
  pull-request and merge gates before retrying; do not silently fall back to a local Debug deploy.
  If a correction changes the published artifact, release a new immutable version rather than
  replacing it or moving a published version tag. Mark a rollout complete only after verification,
  and report declined or deferred deployments separately.

## Release-Version Decision

- Review the full branch diff and commits for consumer impact, not only the pull-request title.
  Classify substantial features, architectural migrations, broad refactors, removed or renamed
  public contracts, incompatible configuration and other breaking behaviour explicitly.
  Diff size alone does not determine a semantic version.
- Inspect the repository's `GitVersion.yml`, release workflow and scoped versioning instructions,
  the latest immutable release tag, and any existing version directives on the branch. Do not
  assume that conventional-commit wording or `BREAKING CHANGE` automatically controls GitVersion.
- Unless semver was explicitly delegated for this train, use a UI choice before merging to ask
  whether to deliberately bump **major**, bump **minor**, or
  retain the **patch/default increment**. Show the current version, expected outcome of each
  choice, and relevant compatibility impact. Recommend major for breaking changes, minor for
  compatible new functionality, and patch for compatible fixes or internal-only refactoring.
  For pre-1.0 packages, explain the repository's established breaking-change policy.
- Wait for an explicit decision unless the user has explicitly delegated semver decisions for the
  named train. Under that delegation, choose and document each repository's increment and rationale
  without asking again. General merge approval or auto-merge does not imply delegation; reconfirm
  material changes outside the delegated scope.
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
