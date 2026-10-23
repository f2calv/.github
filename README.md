# .github

Shared GitHub Copilot instructions, agent skills and PowerShell repository management tools for
maintainers working across multiple repositories. This account-level configuration repository also
provides default GitHub issue forms, pull request templates and contribution guidance.

## Quick Start

1. Clone this repository alongside the repository you are working on.
2. In VS Code, use **File > Add Folder to Workspace** to add this repository, then save the workspace.
3. Select the **Copilot** agent harness and run **Chat: Open Customizations** from the Command Palette.
   Confirm that the shared instructions and skills are available to that session.
4. Ask for a relevant task, or invoke an available skill directly, for example:

   ```text
   /readme-authoring
   ```

The [shared instructions](.github/instructions/) contain language, tool and documentation
conventions. [Skills](.github/skills/) supply task-specific workflows and supporting resources.
Repositories retain their own project-specific instructions rather than copying the shared set.

Discovery depends on the selected agent harness; use the
[VS Code customization documentation](https://code.visualstudio.com/docs/agent-customization/overview)
and the active session's customization view to verify what is loaded.

### Personal Installation

For Copilot sessions across workspaces, link the shared folders into the supported personal
locations instead of keeping this repository open in each workspace. Choose one discovery route
to avoid loading the same files twice.

The examples assume a clone under `source/github/.github` in your home directory. Adjust that
location first, and run them only when the destination links do not already exist. Preserve any
existing personal customizations rather than overwriting them.

Windows PowerShell:

```powershell
$repo = "$HOME\source\github\.github"
New-Item -ItemType Directory -Force -Path "$HOME\.copilot" | Out-Null
foreach ($name in 'instructions', 'skills') {
  New-Item -ItemType Junction -Path "$HOME\.copilot\$name" -Target "$repo\.github\$name"
}
```

macOS and Linux:

```bash
repo="$HOME/source/github/.github"
mkdir -p "$HOME/.copilot"
for name in instructions skills; do
  ln -s "$repo/.github/$name" "$HOME/.copilot/$name"
done
```

These links point at the working tree: local edits and pulled updates become available without
copying files into each consumer repository. Recreate the links on another workstation;
harness-folder customizations do not roam through VS Code Settings Sync.

The repository's own [Copilot instructions](.github/copilot-instructions.md) are project-specific,
not part of the shared installation.

## Skill Catalogue

Use the linked workflow for its prerequisites, safety gates and detailed commands.

| Skill | Use it for |
| --- | --- |
| [README authoring](.github/skills/readme-authoring/SKILL.md) | Consumer-focused documentation for public and private applications, libraries, Actions, workflows and infrastructure |
| [Repository baseline](.github/skills/repository-baseline/SKILL.md) | Auditing and reconciling GitHub settings, default-branch rules and analysis requirements |
| [Repository privacy](.github/skills/repository-privacy/SKILL.md) | Checking public changes for personal data, credentials and private-system details |
| [Issues and pull requests](.github/skills/github-issues-and-pull-requests/SKILL.md) | Issue quality, pull request descriptions, review findings and merge readiness |
| [Archive repository](.github/skills/archive-repo/SKILL.md) | Explicitly requested retirement, archiving and optional local cleanup |
| [Summarize for PR](.github/skills/summarize-for-pr/SKILL.md) | An explicitly requested temporary branch-change summary for review |
| [Dependabot management](.github/skills/dependabot-management/SKILL.md) | Coverage, grouping and troubleshooting across dependency ecosystems |
| [Pre-commit management](.github/skills/pre-commit-management/SKILL.md) | Configured lint hooks, pinned runtimes and native or Docker execution |
| [EditorConfig management](.github/skills/editorconfig-management/SKILL.md) | Shared formatting profiles, analyzer rules and drift |
| [Dev Containers](.github/skills/devcontainer/SKILL.md) | Development images, Features, lifecycle commands and editor integration |
| [Spec Kit bootstrap](.github/skills/spec-kit-bootstrap/SKILL.md) | Spec-driven development setup for new or existing repositories, with a Specify-ready Dev Container |
| [Container images](.github/skills/container-images/SKILL.md) | Dockerfile authoring, image profiles, build strategy and static auditing |
| [Container workflows](.github/skills/container-workflows/SKILL.md) | Shared local container build and GitOps deployment scripts |
| [.NET cleanup](.github/skills/dotnet-cleanup/SKILL.md) | Source layout, naming and analyzer-driven cleanup |
| [.NET exceptions](.github/skills/dotnet-exceptions/SKILL.md) | Throw-site audits and area-specific `GenericException` types |
| [.NET Web API](.github/skills/dotnet-webapi/SKILL.md) | Thin controllers, TypedResults, DTO services and verified HTTP/OpenAPI contracts |
| [.NET MCP](.github/skills/dotnet-mcp/SKILL.md) | Read-only Streamable HTTP tools, registration, contracts and protocol validation |
| [.NET performance](.github/skills/dotnet-performance/SKILL.md) | Measured hot-path, allocation and parsing improvements |
| [.NET release train](.github/skills/dotnet-release-train/SKILL.md) | Dependency-ordered NuGet updates, releases and consumer propagation |
| [.NET test platform](.github/skills/dotnet-test-platform/SKILL.md) | Microsoft.Testing.Platform and xUnit v3 configuration and migration |
| [Leadership election](.github/skills/leadership-election/SKILL.md) | Redlock-backed leader lifecycles, safe failover, shared caching integration and replica-aware validation |
| [Redis data access](.github/skills/redis-data-access/SKILL.md) | Key roles, cache-aside reads, expiry, invalidation, streams and endpoint placement |
| [REST Client requests](.github/skills/rest-client-requests/SKILL.md) | Structured HTTP requests, authentication examples and secret handling |
| [Helm charts](.github/skills/helm-charts/SKILL.md) | Chart contracts, values, dependencies, documentation and OCI packaging |
| [GitOps repository structure](.github/skills/gitops-repository-structure/SKILL.md) | Argo CD Application discovery, ownership and stateful migrations |
| [NGINX ingress migration](.github/skills/nginx-ingress-migration/SKILL.md) | Parallel controller rollout, compatibility mapping, cutover and rollback |
| [UniFi network management](.github/skills/unifi-network-management/SKILL.md) | Network discovery, VLANs, host networking and performance diagnostics |

## Repository Management

Run the following examples from this repository's root. The GitHub management tools require
PowerShell 7.4 or later, Git and an authenticated GitHub CLI account with the permissions required
for the operation.

### Audit Settings

Audit one repository without changing remote settings:

```powershell
.\.github\skills\repository-baseline\scripts\Set-RepositoryBaseline.ps1 `
  -Repository owner/example `
  -Mode Audit
```

Preview changes for the same repository:

```powershell
.\.github\skills\repository-baseline\scripts\Set-RepositoryBaseline.ps1 `
  -Repository owner/example `
  -Mode Apply `
  -WhatIf
```

The [baseline policies](.github/skills/repository-baseline/scripts/policies/) define the settings:
`<owner>.json` when present for the target owner, otherwise the generic `default.json`. Follow the
[baseline workflow](.github/skills/repository-baseline/SKILL.md) before
applying changes; unavailable plan-dependent capabilities are reported rather than bypassed.

### Create a Repository

The [repository creation script](.scripts/New-GitHubRepository.ps1) creates a GitHub repository,
applies the baseline and clones it locally. Choose visibility explicitly; the script defaults to
public visibility.

```powershell
.\.scripts\New-GitHubRepository.ps1 `
  -Name example `
  -Description 'Example repository' `
  -Visibility Private
```

Use `-TemplateRepository owner/template` to start from a template, `-NoClone` to omit the local
clone, or `-AddToWorkspace` to add it to the active VS Code workspace. The owner defaults to the
authenticated GitHub account.

## GitHub Community Defaults

GitHub uses this public account-level repository's defaults for owned public **and** private
repositories that do not supply their own corresponding files:

- [Issue forms](.github/ISSUE_TEMPLATE/) for bugs, feature requests and support.
- [Pull request template](.github/pull_request_template.md) for scope, issue links and validation.
- [Contribution guidance](CONTRIBUTING.md) and [support guidance](SUPPORT.md).

These defaults are a GitHub feature, independent of the local Copilot setup. They do not need to
be copied into consumer repositories. A repository's own issue-template configuration overrides
the default issue-template directory as a whole; consult
[GitHub's inheritance rules](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)
before adding local overrides.

## Development

The central Pester runner discovers root script tests and every skill's `scripts/tests` directory,
including pre-commit management and release-train checks. With PowerShell 7.4+, Pester 5.7.1,
Git, Bash, Helm, Mike Farah yq v4 and npm available, run from the repository root after test approval:

```powershell
npm run test:ps
npm run test:release-train
```

Other skill-specific validation commands and dependencies are documented with the corresponding
skill; invoking a skill does not require running every suite in this repository.
The release-train command is a focused alternative, not a suite omitted by `test:ps`.
CI checks its local tool prerequisites before running the central suite.

### Validation Boundaries

| Evidence | Persistent coverage | Still requires separate execution or approval |
| --- | --- | --- |
| Skill discovery, maintenance sections and local links | Central Pester checks | Editor activation and external links |
| Container and caller templates | Static audit and synthetic argument/exit tests | Image builds, registry publication and deployment |
| Helm/GitOps/ingress examples | Real local Helm render/lint/schema/package checks and structural ownership assertions | Cluster bootstrap, admission, routing, certificates and rollback |
| Forms, policy overrides and cleanup examples | Form comparisons, pure policy composition, mocked APIs and synthetic source edits | Actual GitHub operations and consumer compatibility |
| REST collections and network-change evidence | Static structure, variable and approval-boundary checks | Requests, live network measurements and fault recovery |
| .NET examples and benchmarks | Structural checks; the parsing fixture also contains runnable xUnit tests | Compile/HTTP fixtures, published-package consumption and benchmark execution are not run by the central Pester job |

The .NET compile, loopback HTTP and benchmark checks performed while authoring examples are
point-in-time evidence, not continuous CI coverage. Repeat them after relevant SDK/API changes.
<!-- TODO: Persist the MCP, controller, leadership, exception and release-consumer integration
fixtures and wire an opt-in .NET validation job. Deferred because several examples depend on
consumer authentication or provisional shared-library APIs; select reproducible published
contracts before adding remote restores or live consumers to default CI. The self-contained
parsing tests are the first candidate for that job; benchmarks should remain explicitly requested. -->
