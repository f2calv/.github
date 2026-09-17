---
name: dotnet-release-train
description: 'Plan, prepare, execute, pause, resume, and verify releases across dependent .NET and public NuGet repositories. Use when coordinating package dependency updates, Patch Tuesday upgrades, chained pull requests, GitHub releases, NuGet publication, or downstream application updates.'
argument-hint: '[mode={plan|prepare|run|resume|status|stop}] [roots=...]'
user-invocable: true
---

# .NET Release Train

Coordinate a dependency-ordered release train across .NET repositories in the current VS Code
workspace. The workflow discovers package relationships, validates local source and published-package
builds, manages pull requests, waits for GitHub and NuGet publication, and persists enough state to
resume after hours or days.

This skill orchestrates existing repository workflows. It does not replace CI, calculate versions,
publish packages directly, or deploy applications outside their established workflows.

## Prerequisites

- PowerShell 7.4 or Bash 4.0 or later.
- GitHub CLI authenticated for every repository in scope.
- Git and the required .NET SDKs available in each repository's supported environment.
- A `Directory.Packages.props` file for centrally managed package versions.
- Public package publication through `https://api.nuget.org/v3/index.json`. Authenticated and private
   feeds are outside version 1 scope.
- Existing CI that builds the Release solution and publishes packages from the default branch.
- Required pull request checks configured in repository rulesets.
- An existing local `.copilot-tracking/` workspace folder, or approval to create one outside all
  tracked repositories.

## Modes

| Mode | Behaviour |
| --- | --- |
| `plan` | Discover repositories and package edges, write a checkpoint, and make no changes |
| `prepare` | Prepare the root producer and consumers whose target versions already exist, but perform no remote operations |
| `run` | Present the complete plan, obtain one scoped authorization, then execute it |
| `resume` | Reload a checkpoint, revalidate remote and local state, and request fresh authorization |
| `status` | Report checkpoint and remote state without mutation |
| `stop` | Mark the train stopped without reverting completed releases |

Default to `plan` when no mode is supplied. Never infer permission to push, create pull requests, merge,
or rerun CI from an earlier train.

## Parameters

| Parameter | Meaning |
| --- | --- |
| `mode` | `plan`, `prepare`, `run`, `resume`, `status`, or `stop` |
| `roots` | Optional workspace repository names or absolute paths to use as graph roots |

The dependency graph determines downstream scope. Ask before adding a repository that is not already
open in the workspace or explicitly supplied through `roots`.

## Safety Model

- Treat the dependency graph, repository list, branches, immutable HEADs, commands, and remote
   operations as the unit of authorization. Show all of them before asking for approval.
- Collect run approval and the independent auto-commit and auto-push switches as separate graphical
   questions in one dialog. Run approval never implies either switch. Respect switch changes
   immediately and surface enabled automation at dependency-layer boundaries.
- Authorization exists only in the active conversation. Never persist it. It expires when scope
   changes, the train pauses, the conversation ends, or the checkpoint is resumed.
- Never persist credentials, tokens, authorization headers, or environment values in checkpoint
  state.
- Never publish private repository identities or topology from a checkpoint into a public commit,
  issue, pull request, comment, or log.
- Never alter, stage, or commit unrelated working-tree changes. Preserve each repository's current
  feature branch and existing commits.
- Search for an existing pull request and linked issue before creating either. Follow the central
  GitHub issue and pull request conventions.
- Use a merge commit for an automatically mergeable pull request. Do not squash or rebase it.
- Auto-merge only a dependency-only pull request whose authorized checks pass and whose current base
   ref, base SHA, and head SHA exactly match the values used for classification and check verification.
   Re-fetch both refs and the diff immediately before merge. Any changed base, head, file set, or
   unexpected package edit expires classification and authorization for that merge.
- Never bypass required checks, administrator protections, deployment environments, or failed tests.
- Never treat a successful package push as publication. Continue only after every expected package
  version is available from NuGet's restore endpoint.
- Do not keep a process sleeping for a deliberate multi-hour or multi-day pause. Persist the
  checkpoint, expire authorization, exit cleanly, and resume later.

## Checkpoint

Store each run below the local workspace tracking folder:

```text
.copilot-tracking/release-trains/<yyyy-MM-dd>-<train-name>/state.json
```

Validate state against
[release-train-state.schema.json](./assets/release-train-state.schema.json). Update it atomically after
every state transition. Record timestamps in UTC and append events rather than rewriting history.
Canonicalize the repository keys, immutable HEADs, dependency edges, planned package edits, validation
commands, and remote operations as JSON and store its SHA-256 as `planFingerprint`. Recompute it before
each remote mutation. A mismatch expires run authorization and requires a revised plan.

Repository stages progress through:

```text
discovered -> prepared -> pushed -> pr-open -> checks-passed -> merged
           -> release-complete -> packages-available -> completed
```

Store `stage` separately from `disposition`. Pausing, failing, skipping, or stopping must not erase
the last durable stage. A downstream repository cannot move past `discovered` until every required
upstream package version has recorded NuGet availability evidence.

## Dependency Discovery

1. Consider only Git repositories explicitly open in the current workspace or supplied through
   `roots`.
2. Evaluate projects with MSBuild (`dotnet msbuild -getProperty` and `-getItem`) so imports,
   properties, conditions, `PackageId`, and `IsPackable` are resolved. Parse
   `Directory.Packages.props` as XML for declared package versions. Do not use string replacement.
3. Discover produced package IDs from evaluated projects with `IsPackable=true`. Resolve `PackageId`,
   falling back to the evaluated project name when it is absent.
4. Discover consumed package IDs and exact versions from `Directory.Packages.props` and
   `PackageReference` items.
5. Read Debug and Release solutions plus conditional `ProjectReference` and `PackageReference` items
   to confirm local-source and published-package paths.
6. Build repository edges only when a consumed package ID is produced by another repository in
   scope.
7. Topologically sort the graph into dependency layers. Fail on a cycle and show the exact edges.
8. Present unrecognized package producers and consumers for review. Never silently omit an edge.

The checkpoint owns the discovered graph for that train. On resume, rediscover and compare it; require
a new plan approval when repositories, package IDs, or edges changed.

## Pull Request Classification

A dependency-only pull request may contain only the exact package update files and values shown in
the authorized plan:

- `Directory.Packages.props`;
- committed NuGet lock files;
- generated dependency metadata required by the repository's documented update process;
- release-train checkpoint data only when that data is in an untracked local workspace folder.

An allowed path containing any unplanned package ID, version, metadata, or generated change is mixed.
Treat changes to source, tests, project files, build configuration, workflows, documentation, or any
other path as mixed. Display the full changed-file list, package-value diff, commit summary, and PR
head SHA before asking whether to merge a mixed pull request.

## Required Protocol

### 1. Plan

1. Create or load the checkpoint.
2. Capture each repository's path, visibility, default branch, current branch, HEAD, upstream,
   worktree status, open pull request, linked issue, produced packages, and consumed internal
   packages.
3. Refuse to proceed from detached HEAD, the default branch, an unresolved merge/rebase state, or an
   unexplained dirty worktree. When no feature branch exists, propose a compliant branch name and
   require it in the authorized plan before creating it from a freshly fetched default branch.
4. Discover the dependency graph and show the ordered layers.
5. For each repository, show the exact package edits and Debug/Release build and test commands.
6. Classify every existing branch or pull request as dependency-only or mixed.
7. Calculate and persist the canonical plan fingerprint.

### 2. Authorize

Use one graphical dialog showing the plan plus separate choices for run approval, auto-commit, and
auto-push:

- repositories and branches in order;
- builds and tests that will run;
- commits and pushes that may occur;
- pull requests that may be created or reused;
- dependency-only pull requests eligible for automatic merge;
- mixed pull requests that will pause for approval;
- expected packages and downstream updates.

Offer `Approve run`, `Prepare locally only`, `Revise plan`, and `Stop`. Offer independent enabled or
disabled choices for auto-commit and auto-push. Do not write authorization to the checkpoint.

### 3. Prepare a Producer

1. Recheck HEAD, upstream, worktree, pull request, and issue state against the checkpoint.
2. Review the entire branch diff, including changes unrelated to dependencies.
3. Run the authorized repository validation. Prefer the Debug solution for source-level integration.
4. Run repository lint and every authorized test command before pushing.
5. For a public repository, run the central PII scanner before every commit and inspect the proposed
   commit message, issue, pull request, branch, and comments for private repository identities.
6. Commit only uncommitted changes that belong to the approved train. Commit automatically only when
   auto-commit is enabled for the active session; otherwise pause for explicit commit approval. Keep
   existing commits intact.
7. Push only when auto-push is enabled for the active session. Otherwise pause for explicit push
   approval.
8. Search open and closed issues before creating one. Select and verify the native issue type or
   canonical type label, apply accurate labels, and verify the created issue.
9. Read the repository pull request template, create or update the pull request, link the issue,
   apply accurate labels, assign the authenticated user, and verify base, head, labels, and assignee.

In `prepare` mode, stop after local validation. Do not invent a downstream target version. Prepare a
consumer only when its upstream target version is already verified on public NuGet.

### 4. Merge and Publish

1. Record the PR base ref, base SHA, and head SHA, then wait for all required checks on that exact head
   SHA. Record check-suite and workflow-run identifiers. A cancelled, skipped unexpectedly,
   timed-out, stale, or failed check is a failure, not permission to continue.
2. Immediately before merge, re-fetch the PR base ref, base SHA, head SHA, commits, changed files, and
   package-value diff. If they exactly match the classified evidence and authorized plan, merge a
   dependency-only pull request with a merge commit under the active run authorization.
3. If it is mixed, show its changed files, commits, approvals, and checks in a graphical question.
   Offer `Merge`, `Inspect`, `Pause`, and `Stop`.
4. Record the merge commit and wait for the default-branch CI run associated with that commit.
5. Verify the immutable tag and GitHub release point at the intended release commit. Record the tag,
   release identifier, workflow run, and commit SHA.
6. Derive the release version from the verified tag, not from a local prediction.
7. Enumerate every package expected from the repository and run the bundled NuGet availability
   helper against the public NuGet flat-container endpoint. Record package ID, version, source URI,
   and check time. All packages must report the release version before downstream work starts.
8. For a repository that produces no packages, advance directly from `release-complete` to
   `completed`. Never invent a `packages-available` transition for an application.

### 5. Prepare Consumers

For each direct consumer in the next dependency layer:

1. Update every consumed package from the completed producer to the verified release version.
2. Keep package sets produced by one repository aligned to the same release unless the repository
   explicitly documents an exception.
3. Restore and validate the Release solution against NuGet packages.
4. Validate the Debug solution against local sibling projects when the repository supports it.
5. Follow the same push, pull request, merge, and release protocol as the producer. Run package
   availability only when the consumer itself produces packages.

Process sibling repositories sequentially in version 1. Do not begin the next dependency layer until
all selected repositories in the current layer are complete or explicitly skipped with downstream
impact shown.

### 6. Layer Checkpoint

After each healthy dependency layer, use a graphical question with `Continue`, `Pause`, and `Stop`.

- `Continue` retains run authorization only when the remaining scope and immutable repository HEADs
   are unchanged. It does not change auto-commit or auto-push status.
- `Pause` writes state, expires authorization, and exits.
- `Stop` records the stop reason and exits without reverting published packages or merged commits.

### 7. Resume

1. Load and validate the checkpoint.
2. Re-fetch every repository and compare local/remote commits, PR head SHAs, check suites, workflow
   runs, merge commits, releases, tags, package source URIs, and NuGet availability with recorded
   evidence.
3. Advance state when remote evidence proves a step completed while the skill was inactive.
4. Stop on contradictory evidence, such as a moved tag, changed pull request head, rewritten branch,
   or package version not associated with the recorded release.
5. Present the remaining plan and obtain fresh run, auto-commit, and auto-push decisions.

## Failure Handling

For a recoverable failure, record the command or API operation, exit code, concise output, repository
state, and next safe action. Offer `Retry`, `Inspect`, `Pause`, and `Stop` graphically.

Never retry automatically after:

- a failed or missing required check;
- a merge conflict;
- a changed dependency graph;
- an unexpected package ID or version;
- a mixed pull request awaiting approval;
- a release tag or package integrity mismatch;
- authentication or authorization failure.

A repository may be skipped only after showing every downstream repository that depends on it. A
downstream node remains blocked unless each required package ID and target version already has
availability evidence, independently of the skipped producer's disposition.

## Assets

| Asset | Purpose |
| --- | --- |
| [Test-NuGetPackageAvailability.ps1](./scripts/Test-NuGetPackageAvailability.ps1) | Poll NuGet's restore endpoint from PowerShell |
| [test-nuget-package-availability.sh](./scripts/test-nuget-package-availability.sh) | Poll NuGet's restore endpoint from Bash |
| [Invoke-Tests.ps1](./scripts/Invoke-Tests.ps1) | Run the Pester regression suite for PowerShell helpers |
| [release-train-state.schema.json](./assets/release-train-state.schema.json) | Validate resumable checkpoint state |

## Script Reference

PowerShell:

```powershell
./scripts/Test-NuGetPackageAvailability.ps1 `
   -PackageId Example.Core,Example.Json `
   -Version 1.2.3 `
   -TimeoutSeconds 600
```

Bash:

```bash
./scripts/test-nuget-package-availability.sh 1.2.3 Example.Core Example.Json
```

Both helpers return exit code `0` when every package is available, `1` for invalid input or an
unexpected request failure, and `2` when the deadline expires with packages still unavailable.

## Quick Start

Start read-only discovery:

```text
/dotnet-release-train mode=plan
```

Prepare package updates without remote operations:

```text
/dotnet-release-train mode=prepare
```

Execute an approved plan or resume after a pause:

```text
/dotnet-release-train mode=run
/dotnet-release-train mode=resume
```

## Troubleshooting

| Symptom | Response |
| --- | --- |
| Package push succeeded but restore fails | Poll the restore endpoint until all expected IDs expose the verified version |
| Existing pull request contains source changes | Classify it as mixed and require graphical merge approval |
| Train pauses for days | Resume from state, reconcile remote evidence, and request fresh authorization |
| CI run cannot be tied to the merge commit | Stop; do not infer publication from the latest successful run |
| One package from a multi-package repository is absent | Keep the producer incomplete and block its consumers |
| Dependency graph changed on resume | Re-plan and obtain new authorization |
| Private repository appears in public output | Stop and rewrite the output without the private identifier |
