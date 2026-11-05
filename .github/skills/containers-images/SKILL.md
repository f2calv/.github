---
name: containers-images
description: 'Create, update, migrate and audit Dockerfiles and .dockerignore files: image profiles, workload shapes, build strategy, platforms, runtime base, pinning, caching, provenance, entrypoints and debug variants. Use when authoring or reviewing a Dockerfile, including rules docker buildx build --check misses; Compose stacks belong to containers-docker-compose.'
argument-hint: 'mode={create|update|migrate|audit} [path=Dockerfile-or-directory] [profile={published|single-arch|vendor|debug|sample}]'
compatibility: 'The audit requires PowerShell 7.4. Build validation requires Docker with Buildx; arm platforms on an amd64 host also need QEMU binfmt handlers.'
---

# Container Images

## Overview

Author Dockerfiles that follow `docker.instructions.md` without applying every feature to every
image. Classify the image into a profile, choose only the options it needs, start from the patterns,
then validate with BuildKit and with this skill's audit. BuildKit checks pass on Dockerfiles that
run as root, skip `exec`, leak apt lists or fall through on an unknown platform; the audit catches
those.

## Prerequisites

* Read the target repository's `copilot-instructions.md` and existing Dockerfiles before editing.
* PowerShell 7.4 for `scripts/Test-Dockerfile.ps1`.
* Docker Buildx for `--check` and platform builds. The containerd image store is needed to load a
  multi-platform image with `--load`.

## Quick Start

```text
/containers-images create Dockerfile for a Go service
/containers-images migrate ./Dockerfile
/containers-images audit the workspace
```

| Mode | Contract |
| --- | --- |
| `create` | Classify, choose options, write the Dockerfile and `.dockerignore`, then validate |
| `update` | Preserve the image's behaviour and profile; re-run validation for the changed surface |
| `migrate` | Bring a legacy Dockerfile to its profile; report behaviour changes such as a new `USER` |
| `audit` | Make no edits; report audit findings and `--check` warnings per file |

## Workflow

### Step 1: Classify the Image

Choose the profile, which says how the image is built and published, and the workload shape, which
says how it runs, from the tables in `docker.instructions.md`. Ask when either is not evident.
`single-arch`, `vendor` and `sample` each relax rules and need a stated reason in the header; a
`job` or `tool` shape is declared as `# Shape: <name>`. Archived and playground repositories are
usually better archived than migrated.

### Step 2: Choose Options

Pick each option from [the options reference](references/options.md) and skip what the image does
not need:

* The workload shape's entrypoint, port, input and output conventions.
* Build strategy and platform set.
* Runtime base, confirmed to publish every declared platform.
* Pinning mode, and a Dependabot `docker` entry when digests are used.
* Cache mounts and their `sharing` mode.
* Provenance mode and labels.
* Entrypoint form, writable paths and any debug variant.
* An optional `test` stage, when the repository has credential-free tests.

### Step 3: Author

Start .NET service images from the bundled managed
[published](templates/dotnet-service.dockerfile.tmpl),
[Debug](templates/dotnet-service-debug.dockerfile.tmpl) or
[Native AOT](templates/dotnet-service-aot.dockerfile.tmpl) template. The
[dotnet-aot skill](../dotnet-aot/SKILL.md) owns application compatibility; this skill owns the image.
Use shared version inputs, not per-major template copies; keep .NET 10 usable and gate .NET 11 on
verified GA, tags and target manifests. Native AOT defaults to native builders per Linux amd64/arm64
target, not generic RID cross-publish or a `single-arch` classification. Start other workloads from the
[patterns reference](references/patterns.md) or the matching public `multi-arch-container-*`
repository. Preserve template ordering and formatting; explain workload-required deviations beside
them. Update the `.dockerignore` allow-list for every file the build reads.

Use the [template inputs and worked substitution](./examples/dotnet-service.md) to select the
matching ignore file and resolve every placeholder. The example distinguishes assembly identity
from project paths and shows how sibling-project Debug inputs map into the container.

### Step 4: Validate

Run the audit, then BuildKit's checks:

The script path below is relative to this skill's directory, not the application's repository.
Supply absolute Dockerfile/context paths when invoking BuildKit from that location.

```powershell
./scripts/Test-Dockerfile.ps1 -Path <repository>
docker buildx build --check -f <Dockerfile> <context>
```

Build the native platform and smoke-run it. Ask before building, and before running the optional
`test` target, which executes the repository's tests:

```bash
docker buildx build --pull --platform linux/amd64 --load -t example/app:local -f Dockerfile .
docker run --rm example/app:local
docker buildx build --target test --progress=plain -f Dockerfile .
docker buildx build --pull --platform linux/amd64,linux/arm64,linux/arm/v7 -f Dockerfile .
```

Follow the [validation notes](references/validation-notes.md) for workstation limits, smoke tests,
multi-platform loading, shell-less images and tag casing.

## References

| Reference | Use for |
| --- | --- |
| [Dockerfile conventions](references/dockerfile-conventions.md) | Every rule behind the Docker instructions, with reasons |
| [Audit and scripts](references/audit-and-scripts.md) | `Test-Dockerfile.ps1` parameters, DF rules, manual checks and helper scripts |
| [Validation notes](references/validation-notes.md) | Local build, smoke-test and tagging pitfalls |
| [Troubleshooting](references/troubleshooting.md) | Build and audit failures |
| [Options](references/options.md) and [patterns](references/patterns.md) | Per-image decisions and worked patterns |
| [.NET artifact identity](references/dotnet-artifact-identity.md) | Version and revision contract for .NET images |

## Maintaining This Skill

* Base-image tags, digests and distribution package pins in the examples and audit rules.
* `docker buildx build --check` coverage: drop audit rules the checker now enforces and add the
  ones it still misses.
* Script parameters in the Script Reference whenever the scripts change.
* Keep shared version inputs, verified GA/tag/platform gates, AOT toolchains, globalization,
  ignore-file inputs and entrypoints aligned; exercise managed, Debug and AOT audit regressions.
