---
description: 'Dockerfile and .dockerignore invariants — image profiles, stage layout, multi-architecture builds, layer caching, pinning, provenance and runtime hardening.'
applyTo: '**/Dockerfile,**/Dockerfile.*,**/*.dockerfile,**/.dockerignore'
---

# Docker

Rules that hold for every Dockerfile. Images are deployed to Kubernetes; Compose runs them only for
local development and testing. Choices that vary per image — build strategy, platform set,
runtime base, pinning mode, cache sharing, provenance, entrypoint and debug variants — are made
with the `container-images` skill, which also carries the patterns and a static audit. Compose files
follow `docker.compose.instructions.md`. Dev container Dockerfiles belong to the `devcontainer`
skill and are exempt from this file.

## Image Profiles

Classify the image before applying the rules. The profile states which rules are relaxed; declare
any profile other than `published` in the header comment as `# Profile: <name>`.

| Profile | Use for | Relaxed rules |
| --- | --- | --- |
| `published` | Images CI pushes to a registry (the default) | None |
| `single-arch` | Hardware-bound images that cannot be built or run for other platforms | Native build stage; one declared platform |
| `vendor` | Rebuilds or wrappers of a third-party image | Base pinned to the vendor's commit tag; provenance `ENV` optional |
| `debug` | Variants never published, such as `Dockerfile.Debug` | No labels or provenance block |
| `sample` | Playground and archived repositories | Only pinning, non-root and the secret rules apply |

## File Header

- Start with `# syntax=docker/dockerfile:1`. It tracks every 1.x release of the Dockerfile frontend,
  so heredocs, `COPY --parents`, `--mount` and build checks work on any BuildKit engine without an
  engine upgrade.
- Follow it with a comment block: what the image is, why it is structured this way, and its profile
  when it is not `published`.
- Build clean under `docker buildx build --check`. Use `# check=skip=<rule>` only for a deliberate
  violation and give the reason beneath it. `--check` does not enforce this file; the skill's audit
  does.

## Stages

- One Dockerfile per image, never one per architecture.
- Name every stage. The core stages are `build` and `final`; add one only for a pinned tool image, a
  shared runtime base for an optional `debug` target, an optional `test` target, or an input that
  must come from another image.
- `final` is always the last stage, so a build without `--target` produces the published image and
  never runs an optional stage `final` does not depend on.
- Introduce each stage with a banner comment explaining its base and pin, and mark the dependency,
  compile and provenance blocks with `-- Section --` sub-banners.
- Inside the runtime stage keep this order: `FROM` → `WORKDIR` → runtime package install →
  `COPY --from=build` and runtime configuration → runtime `ENV`, `EXPOSE`, `VOLUME` → provenance →
  `LABEL` → `USER` → `ENTRYPOINT`/`CMD`. Installing packages before the application copy means a
  source edit neither reinstalls them nor stops the install running in parallel with `build`.
- Never leave commented-out instructions; git keeps history. Put investigation tooling in an
  optional `debug` target that derives from the same runtime stage as `final`.

## Multi-Architecture Builds

- Pin every build stage that runs commands to `--platform=$BUILDPLATFORM`. Cross-compile compiled
  languages; build architecture-neutral output (pure-Python wheels, .NET IL, JVM bytecode) once.
  QEMU emulation is typically an order of magnitude slower. Native per-target builds belong to the
  `single-arch` profile and say why in the header.
- Never put `--platform` on `final`; buildx then resolves the runtime base for `$TARGETPLATFORM`.
- Declare `ARG TARGETARCH` and `ARG TARGETVARIANT` after every platform-agnostic layer. Each `RUN`
  after an `ARG` carries its value in the cache key, so an early declaration splits layers that all
  platforms could share.
- Map platforms with a single `case "${TARGETARCH}${TARGETVARIANT}"` whose `*)` arm exits non-zero.
  An unrecognised platform must fail the build, never fall through with an empty value.
- The platform set is a contract between the `case`, the base images, the build scripts, CI and the
  README; change them together. Confirm with `docker buildx imagetools inspect` that every base image
  publishes every platform before adopting it.

## Base Images and Pinning

- Never use `latest` or an untagged image.
- Pin to the narrowest tag that still receives patch updates: major.minor where minor releases can
  change behaviour (`sdk:10.0`, `python:3.14-slim-trixie`). A major-only tag is acceptable in a build
  stage for toolchains with strong compatibility guarantees (`golang:1-trixie`, `rust:1-trixie`).
- Name the distribution release where the image offers one, and move to the current release before
  the previous one leaves its publisher's support window. Never build on a newer distribution than
  the runtime stage uses, or a dynamically linked binary can require a newer glibc than it finds.
- Pin an image that only supplies a copied tool (`COPY --from=<image>`) to an exact version.
- Pin a digest only as `tag@sha256:…` together with an automated updater such as Dependabot's
  `docker` ecosystem. A digest without automated updates stops base-image security fixes arriving.
- Use the smallest runtime that supports every target platform and every framework the application
  actually loads: distroless or chiselled, then slim, then full. List the rejected alternatives,
  smallest first, in the `final` banner.
- Never run `apt-get upgrade` or `dist-upgrade`; pick up patches by rebuilding on a refreshed base.

## Layer Caching

- Copy only dependency manifests and lockfiles, resolve dependencies, then copy sources. Runtime
  configuration such as `appsettings.json` is not a manifest. Use `COPY --parents` for globbed
  manifests.
- Mount package and compiler caches with `RUN --mount=type=cache`. Give per-platform compiler output
  a per-platform `id`, and copy anything produced inside a cache mount out in the same `RUN`.
- Use `sharing=locked` unless the step only reads the cache, or the tool keeps its own lock inside the
  mounted directory. Every platform leg of a multi-platform build mounts the same cache, and a tool
  that locks elsewhere, such as NuGet in its temporary directory, cannot see the other legs. The
  skill lists the per-tool modes.
- Prefer `COPY --link` for `COPY --from=build`. Omit it when the destination path passes through a
  symlink, because a linked layer cannot read the layers beneath it.

## RUN Instructions

- Use heredocs for multi-command steps and open them with `set -eux`. A heredoc returns the status of
  its last command, so without `-e` earlier failures pass silently. Drop `-x` in any step that reads
  a secret mount.
- One logical step per `RUN`; never merge dependency resolution with compilation.
- Run `apt-get update`, `apt-get install -y --no-install-recommends <explicit packages>` and
  `rm -rf /var/lib/apt/lists/*` in one `RUN`, unless `/var/lib/apt` is a cache mount. Install only
  runtime libraries in the runtime stage, never `-dev` packages or meta-packages.
- Never pipe a download into a shell. Fetch a versioned artifact and verify its checksum where the
  publisher provides one.
- Use absolute `WORKDIR` paths; never rely on `cd` between instructions.

## Reproducibility

- Install from a committed lockfile in locked mode where the ecosystem has one, so drift fails the
  build: `cargo --locked`, `uv export --locked` with `pip --require-hashes`, `go.sum`, NuGet
  `packages.lock.json` with `--locked-mode`.
- Strip absolute paths and debug symbols from compiled binaries where the toolchain supports it.
- Keep every input deterministic except the deliberately floating base tag and distribution packages.
  Never read the host clock, host state or an unpinned download. Provenance and SBOM attestations
  record what the floating inputs resolved to.

## Provenance and Labels

- A `published` image declares `GIT_REPOSITORY`, `GIT_BRANCH`, `GIT_COMMIT`, `GIT_TAG`,
  `GITHUB_WORKFLOW`, `GITHUB_RUN_ID` and `GITHUB_RUN_NUMBER` as build arguments with safe defaults
  (`n/a`, `0`) so it builds by hand. Mirror them into `ENV` when the application reads them.
- Set the OCI keys `title`, `description`, `source`, `licenses`, `version` and `revision` in one
  `LABEL`. Labels live in the image configuration; a registry that describes multi-architecture
  images from index annotations also needs `--annotation index:<key>=<value>` at build time.
- Build arguments are visible in image history and provenance attestations; only public values
  belong in them.

## Runtime Hardening

- Run as non-root and say so explicitly, even when the base already does: the base image's
  documented UID variable (`$APP_UID`), `nonroot:nonroot` on distroless `:nonroot` tags, otherwise
  numeric `65532:65532`. Place `USER` after the last instruction that needs root.
- Use exec form for `ENTRYPOINT` and `CMD`; a shell stays PID 1 and does not forward `SIGTERM`.
  Resolve a value known at build time into a fixed entrypoint. When expansion at start-up is
  unavoidable, use `["sh", "-c", "exec <command> ${VAR}"]`, which needs a shell in the image.
- Apply the credential rules in `workflow.instructions.md`. In an image this means no credential,
  token, key or connection string in `ARG`, `ENV`, `COPY` or `LABEL`; use
  `RUN --mount=type=secret` at build time and orchestrator-injected secrets at runtime. Copied
  configuration holds only safe defaults, each overridable by environment variable.
- Design for a read-only root filesystem. Create every writable path — volumes, state and cache
  directories — in the image, owned by the runtime user; a mount point that does not exist is created
  root-owned.
- Listen on ports above 1024 and `EXPOSE` them. Docker lowers the unprivileged-port floor inside
  containers, but not every runtime does.
- Never add `HEALTHCHECK`. Kubernetes, the only deployment target, ignores it in favour of probes,
  and Compose declares its own `healthcheck:`.
- Leave no compiler, SDK or build toolchain in the runtime image. An interpreted runtime that ships
  its own package manager is exempt when it is the smallest maintained runtime for every target
  platform; note the exemption in the `final` banner.

## .dockerignore

- Every build context has an allow-list `.dockerignore`: `*` first, then `!` entries for exactly what
  the build reads, then re-exclusions of build output beneath them (`**/bin`, `**/obj`, `**/target`).
  It keeps local secrets out of the context and stops unrelated edits invalidating cached layers.
- A Dockerfile that needs a wider context gets its own `<Dockerfile-name>.dockerignore` beside it
  instead of widening the shared file.
- Update the allow-list in the same change as the Dockerfile that starts reading a new file.

## Validation

- After changing a Dockerfile or its packaging, run the skill's audit, build every declared platform
  and smoke-run the native image. The `container-workflows` skill owns the local build scripts.
