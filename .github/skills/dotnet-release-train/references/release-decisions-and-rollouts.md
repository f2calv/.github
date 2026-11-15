# Release Decisions and Workload Rollouts

How the train chooses each release version and rolls released workloads out to Kubernetes.

## Upfront Agreement

Gather foreseeable questions into one UI batch with recommendations and compatibility risks;
reuse decisions already given.

- Confirm the repositories, package-update scope, documented holds and excluded work.
- Batch needed minor/major decisions or obtain explicit semantic-versioning delegation, including
  breaking changes, pre-1.0 policy and retired framework targets. Follow the
  [version decision procedure](#release-version-decision).
- Settle build, test and integration prerequisites and missing publishing or analysis setup.
  Confirm task-scoped commit, push, pull-request and merge permissions without changing the global
  auto-commit or auto-push switches.
- Confirm whether deployments are excluded or included. If included, collect named applications,
  environments, rollout timing and exact versions or an explicit bounded selection rule under the
  [rollout procedure](#clean-semver-workload-rollouts).
- Offer interactive execution or explicitly approved unattended execution. Summarize the agreed
  scope, permissions, version policy, exclusions and stop conditions before starting.

In unattended mode, execute routine decisions within that agreement without asking again per
repository. It grants no blanket permission and waives no validation, security, merge or immutable
release gate. Stop for unresolved failures, secrets, conflicting instructions, material changes
outside the agreement or decisions its policy cannot resolve; never guess permission. On resume,
retain the agreement but recheck current evidence and ask only about changed scope or unresolved
decisions. Use the existing conversation or task notes, not a new release state file.

## Repository Preparation

- Before releasing a producer, confirm every consumer's Release graph is complete: a reference
  that exists only as a Debug `ProjectReference`, with no Release `PackageReference`, blocks the
  consumer's Release build after the producer ships. Fix the graph on the consumer's branch before
  releasing the producer. Identify producer references by evaluated project paths within its
  repository, not name prefixes that can include unrelated, similarly named projects.
- For a repository's first package release, confirm that CI actually publishes. An application
  repository may only build and test, so add a default-branch `package` job using the shared NuGet
  publish action, mirroring an existing app-plus-package repository, and gate `release` on it. Ask
  the user to create the nuget.org Trusted Publishing policy (owner, repository, `ci.yml`) before
  merging. Replace "no NuGet listing" README caveats with install commands and badges in the same
  pull request.

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

## Package Publication Verification

- Take package IDs from the `.nupkg` files CI created or pushed, or from each project's evaluated
  `PackageId`. Global tools often set a short `PackageId` such as `yamlizr`, so a project file name
  is not a reliable package ID.
- Check the publication action's branch gates before choosing a workflow-dispatch ref.
  For example, `gha-dotnet-nuget` publishes stable packages from the default branch, not a tag dispatch.
  Recover missing packages using the exact release source without rebuilding or replacing an
  already-published image or chart; skipped publication steps are not success.
- From this skill's directory, PowerShell:
  `./scripts/Test-NuGetPackageAvailability.ps1 -PackageId <ids> -Version <version>`.
  Invoke it in-process with `&`; `pwsh -File` binds an array of IDs positionally and fails.
- Bash: `./scripts/test-nuget-package-availability.sh <version> <ids>`

## Clean-SemVer Workload Rollouts

Development deployments through `deploy.ps1` may still be running Debug images after a successful
pull-request merge and release. During the skill's [upfront decisions](../SKILL.md#upfront-decisions),
ask which applications and environments may receive clean-semver releases through GitHub workflows,
and whether to roll out after each release, at agreed milestones, at the end of the train or not
at all. Respect existing publication and deployment holds.

- Let the user choose end-of-train rollouts or batches at useful milestones. Keep deferred
  applications and their verified versions in the existing task list, not a separate release state
  machine, and revisit them at the selected milestone and before the final report.
- Obtain explicit dispatch approval for the named application/environment and exact version,
  individually or as a clearly identified batch. For unattended execution, the user may instead
  explicitly approve a bounded version-selection rule, such as the next verified clean-semver
  release produced by this train for each named application/environment. Match the actual release
  to that approval before dispatch and report its resolved version. Deferral alone is not approval;
  ask when due only if the upfront agreement did not authorize dispatch. Merge, release, auto-push
  and prior Debug-deployment permissions do not authorize these workflow runs.
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
- GitVersion handles patch increments automatically. Do not ask for patch-version approval or add
  a patch directive for routine fixes or internal-only refactoring; verify its computed version.
- During the skill's [upfront decisions](../SKILL.md#upfront-decisions), batch questions only for
  deliberate minor or major increments, unless semantic versioning was explicitly delegated for
  this train. Show current versions, proposed outcomes and compatibility impact. Recommend major
  for breaking changes and minor for compatible new functionality. For pre-1.0 packages, explain
  the repository's established breaking-change policy.
- Wait for those explicit decisions or semantic-versioning delegation before execution. Reuse them
  before each merge; under delegation, choose and document each repository's increment and
  rationale without asking again. General merge approval, auto-merge or unattended mode alone does
  not imply versioning delegation. Ask again only when a material change falls outside the agreed
  policy. Automatic patch increments need no separate decision.
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
