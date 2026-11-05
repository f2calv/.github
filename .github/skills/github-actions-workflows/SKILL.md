---
name: github-actions-workflows
description: 'Create, align, audit and refactor GitHub Actions CI and deployment workflows using the shared reusable workflows and composite actions in gha-workflows. Use for a new repository''s ci.yml, adopting or changing a shared workflow, releasing a shared-workflow or Action change safely, required-check renames, and diagnosing startup failures, permission errors and skipped-but-passing checks.'
argument-hint: 'mode={create|align|audit|release} [archetype=library|app|action|terraform|minimal] [repository=path]'
---

# GitHub Actions Workflows

Build repository CI from the shared building blocks rather than inline steps, and change those
building blocks without breaking their callers. The always-on
[Actions instructions](../../instructions/github.actions.instructions.md) own the invariants: pinning,
permissions, naming, YAML style, security and release rules. This skill owns the workflow.

## Shared Building Blocks

The catalogue, inputs and permission contract for each item live in the
[gha-workflows README](https://github.com/f2calv/gha-workflows#readme); consult it before writing a
caller. Reach for these before writing any inline job:

| Need | Building block |
| --- | --- |
| Lint (pre-commit, actionlint, zizmor) | `lint.yml` |
| Version, tag and release | `gha-release-versioning.yml` |
| NuGet library build, test, pack and push | `gha-dotnet-nuget` composite action in a local `build` job; never a cross-repository reusable workflow, because nuget.org Trusted Publishing rejects it (see the NuGet instructions) |
| .NET, Go, Python or Rust build and tests | `app-build-dotnet.yml`, `app-build-go.yml`, `app-build-python.yml`, `app-build-rust.yml` |
| Container image, Helm chart, chart lint | `container-image-build.yml`, `helm-chart-package.yml`, `helm-lint.yml` |
| GitOps manifest bump | `gitops-helm-update.yml` |
| Terraform validate, test, plan, apply | `terraform.yml` |
| EF Core migration drift | `ef-migrations-drift.yml` |
| Action README major-tag check | `readme-ref-check.yml` |
| Clone sibling repositories, read devcontainer tool versions | `clone-extra-repos` and `devcontainer-tool-versions` composite actions |

Keep a job inline only when it validates something specific to the repository, such as a chart
script test. Two inline copies of the same job are a candidate for a new building block.

## Templates

Start a repository's `.github/workflows/ci.yml` from the matching template, then replace the
placeholders (`Example`, `charts/example`):

| Archetype | Template |
| --- | --- |
| NuGet library | [ci-nuget-library.yml](./templates/ci-nuget-library.yml) |
| Application with image and chart | [ci-app.yml](./templates/ci-app.yml) |
| GitHub Action | [ci-action.yml](./templates/ci-action.yml) |
| Terraform module | [ci-terraform-module.yml](./templates/ci-terraform-module.yml) |
| Documentation, GitOps or configuration | [ci-minimal.yml](./templates/ci-minimal.yml) |

## Workflow

### 1. Inventory

1. List each workflow's jobs, `uses:` references and inline steps.
2. Run `actionlint` and `zizmor` (via the repository's pre-commit, or the `tooling-pre-commit` skill).
3. Note the required status checks from the repository-baseline policy before renaming any job.

### 2. Compose The Caller

1. Pick the template and building blocks; delete inline jobs a building block replaces.
2. Grant each calling job the union of its callee's job permissions. GitHub validates every nested
   job's permissions at startup, including jobs an `if:` would skip.
3. Forward dispatch-only inputs only on `workflow_dispatch`:
   `${{ github.event_name == 'workflow_dispatch' && inputs.push-preview }}`.
4. Build dynamic JSON, such as `extra-repos`, in a `jq` step and pass it as an output.

### 3. Validate A Caller

1. `actionlint`, `zizmor` and the full pre-commit suite.
2. Pull-request CI. Without a pull request, dispatch `ci.yml` on the feature branch only when it has no
   side effects off the default branch; a workflow that pushes images or charts on dispatch does.
3. When a job now calls a reusable workflow, its check becomes `<job> / <callee job>`. Update the
   policy and apply it with the `github-repository-baseline` skill before merging, or the pull
   request blocks on a check that never reports.

### 4. Change A Shared Building Block

Follow the [shared workflow authoring reference](references/shared-workflow-authoring.md) for file
naming, packaging coordinates and release validation.

1. Keep the change backward-compatible for every caller found in an audit of all workspaces and
   owned repositories; record any removal as breaking in the pull request.
2. Extend the shared-workflows self-tests and fixtures to exercise the change.
3. An Action repository self-tests the Action from the commit under review with `uses: ./` against
   a fixture, with publication switched off. For a behaviour no fixture can reach, canary it: point a
   real caller at the branch ref on a temporary branch, dispatch it, then delete the branch. Prefer
   self-tests to a dedicated test repository.
4. A new composite action used by the workflows ships in two releases: publish the action, then
   switch the workflows to `@v1`.
5. Merge to release; the floating aliases move. Re-run one real caller against the released tag.

### 5. Report

List callers changed, check names renamed, validation evidence (job and test counts, not exit codes
alone), and anything deliberately deferred.

## Pitfalls

| Symptom | Cause and fix |
| --- | --- |
| `startup_failure`, no logs | Workflow-file error. Read the run page: usually a nested job requesting more permission than the caller grants |
| A normalised value is ignored | A job or step `env:` of the same name overrides `GITHUB_ENV`; read raw inputs as `IN_*` |
| `format()` JSON is invalid | Literal braces need `{{ }}`; better, build JSON with `jq` |
| Pull request `BLOCKED`, all checks green | A required check name changed; update the ruleset policy |
| nuget.org push fails with `401` from the token exchange | The push runs inside a reusable workflow from another repository; nuget.org Trusted Publishing validates `job_workflow_ref`. Move the push into a local job |
| Dependabot pull request passes without testing | An actor-skipped job counts as passing; skip side effects, not validation |
| Self-test tags the shared-workflows repository | A nested release ran; pass `release: false` or guard by repository |
| Long-standing workaround such as `chart-testing-cli-command: skip` | Check the callee's history: the defect may already be fixed upstream |
| Pinned tool fails on a new language version | Bump the pinned tool, such as staticcheck for a new Go release |
| actionlint rejects a newly supported hosted-runner label | Verify a successful GitHub job used that exact label, then list only those verified labels in `.github/actionlint.yaml`; remove the workaround when actionlint recognises them |

## Maintaining This Skill

- The building-block table and templates when gha-workflows adds, renames or retires a workflow.
- Pitfalls observed while changing shared workflows; keep invariants in the instructions file.
- Validate templates with `actionlint` after every change.
