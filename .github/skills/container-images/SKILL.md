---
name: container-images
description: 'Create, update, migrate and audit Dockerfiles and .dockerignore files against the shared container image conventions. Use when writing a new image, choosing an image profile, workload shape (service, job or command-line tool), build strategy, platform set, runtime base, pinning, cache sharing, provenance, entrypoint, debug variant or optional test stage, modernising a legacy Dockerfile, or checking the rules that docker buildx build --check does not enforce.'
argument-hint: 'mode={create|update|migrate|audit} [path=Dockerfile-or-directory] [profile={published|single-arch|vendor|debug|sample}]'
user-invocable: true
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
/container-images create Dockerfile for a Go service
/container-images migrate ./Dockerfile
/container-images audit the workspace
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

Start from [the patterns reference](references/patterns.md) or the matching public
`multi-arch-container-*` repository. Keep comments explaining every non-obvious choice, and update
the `.dockerignore` allow-list for every file the build reads.

### Step 4: Validate

Run the audit, then BuildKit's checks:

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

* Run one image build at a time on a workstation, and build the full platform matrix only when the
  change is platform-specific; CI builds every platform. Measured on a Windows laptop with Docker
  Desktop in September 2026, a three-platform build took about 20 seconds for the .NET sample and
  12 minutes for the Rust sample, and parallel multi-platform builds forced a reboot.
* A service that needs deployment configuration, such as a mounted certificate, exits at start-up in
  a bare `docker run`. That still proves the image starts and reads its configuration; confirm the
  failure names the missing input.
* `--pull` stops a stale local base image masking a broken build.
* Without the containerd image store, `--load` accepts one platform; use
  `--output type=oci,dest=image.tar` or a push to keep every platform.
* Chiselled and distroless images have no shell, so `docker exec` cannot inspect them. Inspect a
  volume by mounting it into a throwaway image instead, for example
  `docker run --rm -v <volume>:/data busybox:1.37 stat -c %u /data` to check its owner.
* Keep registry, repository and tag values lowercase. Docker only requires the repository name to be
  lowercase, and a tag must match `[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}`, but build scripts run on both
  case-insensitive Windows and case-sensitive Linux file systems, where mixed case causes mismatches.
  Sanitise branch names, which contain `/`, before using them as tags.
* The build workflow attaches `--provenance=mode=max --sbom=true` when attestations are enabled.
* Use the `container-workflows` skill for the repository's scripted local builds.

## Parameters Reference

`scripts/Test-Dockerfile.ps1`:

| Parameter | Default | Description |
| --- | --- | --- |
| `-Path` | `.` | Dockerfiles or directories. Directories skip `.git`, `.devcontainer`, `node_modules`, `bin`, `obj`, `target` and `deps` |
| `-ImageProfile` | `auto` | `auto` reads `# Profile: <name>`, treats `*.Debug` as `debug`, else `published` |
| `-ContextPath` | Nearest `.git` ancestor | Build context used to find `.dockerignore` |
| `-Skip` | none | Rule identifiers to suppress |
| `-FailOn` | `error` | `error`, `warning` or `never` |

Exit codes: `0` no blocking findings, `2` blocking findings, `1` the audit failed.

## Audit Rules

| Rule | Severity | Finding | Relaxed for |
| --- | --- | --- | --- |
| DF001 | error | Missing or unexpected `# syntax` directive | sample |
| DF002 | error | Untagged or `latest` image | |
| DF003 | error | `--platform` on the final stage | single-arch, sample |
| DF004 | warning | A build stage that runs commands is not pinned to `$BUILDPLATFORM` | single-arch, vendor, sample |
| DF005 | error | No `USER`, or `USER root`, in the final stage | |
| DF006 | error | Shell-form `ENTRYPOINT` or `CMD` | sample |
| DF007 | error | `sh -c` entrypoint without `exec` | sample |
| DF008 | error | apt install without `--no-install-recommends` | sample |
| DF009 | error | apt lists not removed in the same `RUN` and not cache-mounted | sample |
| DF010 | error | Distribution-wide package upgrade | sample |
| DF011 | error | Shell heredoc that does not open with `set -e…` | sample |
| DF012 | error | Platform `case` without `*)`, or `if` chain without `else` | sample |
| DF013 | error | Provenance `ARG` without a default | debug, sample |
| DF014 | error | Provenance `ARG` missing from the final stage | vendor, debug, sample |
| DF015 | error | Required OCI label missing | debug, sample |
| DF016 | error | `HEALTHCHECK` declared | sample |
| DF017 | error | Download piped into a shell | |
| DF018 | warning | Commented-out instruction | sample |
| DF019 | error | No `.dockerignore` for the build context | sample |
| DF020 | error | `.dockerignore` does not start with `*` | sample |
| DF021 | warning | `-dev` or meta-package installed in the runtime stage | sample |
| DF022 | error | Secret-like `ARG` or `ENV` with a value | |
| DF023 | warning or error | Last stage not named `final`, or no `FROM` | sample |
| DF024 | warning | `EXPOSE` in a `job` or `tool` image | sample |
| DF025 | warning | `.dockerignore` re-excludes a build or VCS directory without a trailing `/**` | sample |

Rules about the published image follow `FROM <stage>` inheritance, so `FROM runtime AS final`
inherits the runtime stage's `USER`, entrypoint, provenance and labels. Stages derived from the
runtime, such as `debug`, are not expected to run on `$BUILDPLATFORM`.

Rules that need judgement stay manual. Check each by hand when authoring or migrating:

* Dependency manifests are copied before sources, and runtime configuration such as
  `appsettings.json` only after restore.
* `TARGETARCH` is declared late, and runtime packages are installed before the application copy.
* Restore and publish use the same configuration, and a RID-specific publish runs `--no-restore`.
* Every stage that reads a build argument redeclares it with a default.
* Each `VOLUME` path exists in the image, owned by the runtime user.
* The base image is the smallest suitable one, still inside its publisher's support window.
* Lockfiles are installed in locked mode.

The audit reads Dockerfiles and `.dockerignore` files only. Review Compose files against
`docker.compose.instructions.md`.

## Script Reference

```powershell
./scripts/Test-Dockerfile.ps1 -Path ./Dockerfile
./scripts/Test-Dockerfile.ps1 -Path ./Dockerfile.gpu -ImageProfile single-arch
./scripts/Test-Dockerfile.ps1 -Path ~/source/example -FailOn warning | Format-Table Rule, Line, Message
./scripts/Invoke-Tests.ps1
```

Pass several paths as a comma-separated list from PowerShell. From another shell, run
`pwsh -Command "./scripts/Test-Dockerfile.ps1 -Path a,b"`.

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| `no match for platform in manifest` | The base image does not publish that platform; inspect it and drop the platform or change the base. A per-architecture vendor tag can fail like this under `--check` even when `docker pull --platform` succeeds; validate that image with a native build on its target architecture |
| `unsupported platform` from the `case` | Add the platform deliberately across the contract, or remove it from the build command |
| `MSB4024` loading `nuget.g.props`, "Root element is missing" | Local `obj/` files reached the context as empty stubs; re-exclude `**/obj/**` rather than `**/obj` (DF025) |
| `NETSDK1083` naming a semicolon-separated identifier | Quote the RID list as shown in the .NET pattern instead of escaping `;` as `%3B` |
| Container ignores `docker stop` for ten seconds | The entrypoint shell is PID 1; use exec form or `exec` |
| Entrypoint starts `dotnet .dll` | A stage reads a build argument it declared without a default; redeclare it with the default |
| Non-root process cannot write a volume | Create the path in the image, owned by the runtime user, before `VOLUME` |
| `/bin/sh: set: Illegal option -` | The Dockerfile has CRLF line endings; renormalise it under the shared `.gitattributes` (`* text=auto eol=lf`) |
| DF018 on prose comments | Reword comments that begin with an uppercase instruction keyword |

> Brought to you by f2calv/.github
