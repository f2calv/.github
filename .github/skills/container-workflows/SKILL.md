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
./scripts/Invoke-Build.ps1 -RepositoryRoot /src/example
./scripts/Invoke-Deploy.ps1 -RepositoryRoot /src/example -WhatIf
```

## Parameters Reference

`Invoke-Build.ps1` builds every repository the same way, whatever its language. Each Dockerfile
accepts the shared `VERSION`, `CONFIGURATION`, `WORKLOAD`, `GIT_*` and `GITHUB_*` build arguments
and ignores any it does not declare.

| Option | Behavior |
| --- | --- |
| (none) | Validates the build for `linux/amd64,linux/arm64,linux/arm/v7` into the build cache only |
| `-Load` | Loads a single-platform image, the host platform by default, into the local image store |
| `-Run` | Loads the image as `-Load` does, then runs it interactively |
| `-Push` | Publishes the image to GHCR |
| `-Configuration` | Defaults to `Debug` when the repository has a `Dockerfile.Debug`, otherwise `Release` |
| `-Platforms` | Overrides the target platforms |
| `-WorkloadName` | Selects the assembly through the `WORKLOAD` build argument |

A Debug build mirrors the sibling repositories named by `COPY deps/<name>` lines in
`Dockerfile.Debug` into `deps/`. The image is named `ghcr.io/<owner>/<repository>`, where the owner
is read from the repository's GitHub `origin` remote.

The build resolves a semantic version from an explicit `-Version` value or GitVersion and passes it
as the image's `VERSION` build argument. Mutable local tags such as `latest-dev` select an image but
never redefine the version.

`Invoke-Deploy.ps1` reads deployment-specific defaults from the caller's gitignored
`deploy.local.psd1`. Explicit command-line parameters take precedence.

The deployment script reads each Argo CD manifest's `kind` and supports both `Application` and
`ApplicationSet`. It patches `.spec.source` for an `Application` and
`.spec.template.spec.source` for an `ApplicationSet`, failing on any other resource kind.

The pushed tag is mutable, so the script resolves its registry digest and writes the image tag as
`<tag>@sha256:<digest>` with `pullPolicy: IfNotPresent`. Every rollout is therefore traceable to
one image, and a pod reschedule cannot silently pick up a later push of the same tag.

Grafana dashboards ship inside the application chart as a `file://` subchart, so a `-Chart`
deployment publishes and rolls them out with the application. There is no separate dashboard
chart, manifest or deployment mode.

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
| Workstation is sluggish after a reboot | Docker restarts every idle per-repository builder the scripts created (`<image>1`). Stop them with `docker stop` on the `buildx_buildkit_*` containers; the scripts start them again when needed |
| GHCR owner cannot be derived | Add a GitHub `origin` remote; the image namespace is its owner |
| Laptop runs out of memory during builds | Run one scripted build at a time; each multi-platform build emulates arm under QEMU in its own builder |

## Maintaining This Skill

- Parameters and behaviour of the central build and deploy scripts, kept in step with their tests.
- The repository-root shim contract whenever a consumer needs a new switch.
- The shared build-argument names every Dockerfile is expected to accept.
