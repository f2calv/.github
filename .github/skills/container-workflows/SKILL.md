---
name: container-workflows
description: 'Run and maintain centralized container build and GitOps deploy scripts used by repository-root shims.'
argument-hint: '[build|deploy] [repository=path] [options...]'
user-invocable: true
---

# Container Workflows

Build container images and deploy application artifacts without copying orchestration logic between
repositories. Repository-root PowerShell and Bash files remain stable entry points and resolve the
implementations bundled here.

## Prerequisites

- PowerShell 7.4 or later
- Docker Buildx for builds
- Git and yq for deployments
- GitHub CLI and Helm for publication
- Pester 5.7.1 when changing this skill

## Quick Start

```powershell
./scripts/Invoke-Build.ps1 -RepositoryRoot /src/example -BuildMode Application
./scripts/Invoke-Deploy.ps1 -RepositoryRoot /src/example -WhatIf
```

## Parameters Reference

`Invoke-Build.ps1` requires a repository root and one build profile:

| Profile | Behavior |
| --- | --- |
| `Application` | Debug and Release images with Dockerfile-discovered sibling dependencies |
| `SignalCli` | Release-only Generic Host sample image |
| `Yamlizr` | Versioned CLI image with startup smoke checks |
| `MultiArch` | Interactive multi-architecture sample build |

`Invoke-Deploy.ps1` reads deployment-specific defaults from the caller's gitignored
`deploy.local.psd1`. Explicit command-line parameters take precedence.

## Script Reference

Repository shims resolve scripts from `~/.copilot/skills/container-workflows/scripts` first, then
from a sibling `.github` checkout. Run all centralized regressions after changing either script:

```powershell
./scripts/Invoke-Tests.ps1
```

The root `build.sh` and `deploy.sh` files are compatibility launchers, not separate implementations.
They invoke the corresponding root PowerShell shim and therefore require `pwsh` on `PATH`. This
retires duplicated Bash deployment logic and keeps one Pester-covered implementation per workflow.

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| Shared script is missing | Link the central skills folder into `~/.copilot` or clone `.github` beside the caller |
| Debug dependency is missing | Clone it beside the caller or use a Release build |
| Manifest kind is rejected | Use an Argo CD `Application` or `ApplicationSet` |
| Registry authentication fails | Refresh GitHub CLI authentication with `write:packages` scope |

> Brought to you by f2calv/.github
