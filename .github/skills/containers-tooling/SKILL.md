---
name: containers-tooling
description: 'Set up, select and troubleshoot local container tooling: Docker Desktop, Podman with an optional Desktop UI, Windows Linux machines, Compose providers, endpoints, registry trust and builder capabilities. Use when installing or switching container tools, removing a Docker Desktop dependency, or checking workstation compatibility. Compose stacks, image authoring and Dev Containers remain with their owning container skills.'
---

# Container Tooling

Choose a supported toolchain before changing application manifests. A desktop application, container
engine, Compose provider and image builder are separate components; a compatible CLI is not proof
that every API or build feature works.

## Scope and Safety

| Mode | Outcome |
| --- | --- |
| `setup` | Install an approved toolchain and verify its selected endpoint |
| `select` | Choose an existing engine/provider without changing application behavior |
| `audit` | Read-only compatibility findings; no installation or workload changes |
| `diagnose` | Trace an endpoint, networking, registry, mount or capability failure |

Ask before installation, virtualization changes, machine start/stop, sensitive mounts, rootful
mode, user settings, pulls, builds or runtime checks. Tests require separate approval.
Never launch Docker Desktop as an automatic fallback. Do not change global aliases, contexts or
environment variables to hide a failure. Never prune or delete volumes without explicit approval.

## Workflow

### 1. Discover the Actual Toolchain

Identify the OS, repository/workspace scope, applicable software policy, installed executables and
versions. Distinguish client-only discovery from engine calls that can activate services.
Read the relevant setup guide:

* [Docker Desktop](references/setup.md#docker-desktop) for the official download and onboarding.
* [Podman](references/setup.md#podman) for CLI/optional Desktop installation, machine setup,
  independent Compose installation and endpoint verification.
* [Other approved alternatives](references/setup.md#other-approved-alternatives) when neither fits.

Do not assume the presence of `docker` proves Desktop is running or permitted. Conversely, removing
Desktop can remove its bundled Docker CLI, Compose and Buildx.

### 2. Select Engine, Provider and Builder Separately

Use the [capability matrix](references/compatibility.md) to record the selected engine endpoint,
Compose provider/version, builder/version and target platforms. With both engines installed, require
deliberate selection rather than trying another engine after a command fails.

Prefer process-local options/environment for a bounded operation. Detect conflicting `DOCKER_HOST`,
`DOCKER_CONTEXT` and provider configuration before starting workloads. Keep workstation choices out
of tracked repository settings unless that repository deliberately requires one runtime.

### 3. Verify Required Capabilities

Start with static review. With approval, test the smallest representative dependency stack, then
its actual callers, mounts and networking. Follow the [compatibility checks](references/compatibility.md#verification)
and [troubleshooting guide](references/troubleshooting.md).

Validate advanced Dockerfile features, Buildx output modes, GPU devices and nested engine access
independently. A successful Compose parse does not prove runtime health, and a local native build
does not prove a multi-platform publication or its attestations.

### 4. Hand Off Without Duplicating Ownership

* [Compose](../containers-docker-compose/SKILL.md) owns stack topology, profiles and safe validation.
* [Images](../containers-images/SKILL.md) owns Dockerfiles, ignore files and image contracts.
* [Container workflows](../containers-workflows/SKILL.md) owns shared build/deploy scripts.
* [Dev Containers](../containers-devcontainer/SKILL.md) owns editor configuration and lifecycle.

Keep Dockerfile, Compose and Dependabot ecosystem names intact. Change application files only for
an evidenced incompatibility, not because a different engine was selected.

### 5. Report and Clean Up

Report versions, endpoint/provider/builder selection, commands and exact capabilities checked.
Classify each as passed, failed, blocked or not applicable. Record pre-existing workloads first;
stop only task-started resources when their checks finish and preserve volumes/account state.
Never label an unavailable check as a pass.

## Maintaining This Skill

* Recheck official installation paths, Windows machine providers and installed CLI help.
* Reverify Compose provider selection, Docker API compatibility and independently packaged binaries.
* Update capability evidence when Podman/Buildah, BuildKit, VS Code or GPU integration changes.
* Keep host networking, certificate trust and rootless storage guidance aligned with upstream behavior.
