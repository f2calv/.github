---
description: 'Dockerfile and .dockerignore invariants — image profiles, workload shapes, stage layout, multi-architecture builds, layer caching, pinning, provenance and runtime hardening.'
applyTo: '**/Dockerfile,**/Dockerfile.*,**/*.dockerfile,**/.dockerignore'
---

# Docker

Invariants for every Dockerfile. The `containers-images` skill makes per-image choices, audits and
holds the [full conventions with their reasons](../skills/containers-images/references/dockerfile-conventions.md).
Compose files follow `docker.compose.instructions.md`; dev container Dockerfiles belong to the
`containers-devcontainer` skill and are exempt.

## Classification

- Classify each image by **profile** (`published` default, `single-arch`, `vendor`, `debug`,
  `sample`) and **workload shape** (`service` default, `job`, `tool`), and declare any non-default
  in the header comment. Only the profile's documented relaxations apply.
- Jobs and tools never wait for input, write their product to stdout or a mount and diagnostics to
  stderr, report the result as the exit code and read credentials from the environment, never from
  arguments.

## Structure

- Start with `# syntax=docker/dockerfile:1` and a header comment; build clean under
  `docker buildx build --check`, with a reasoned `# check=skip=` only for deliberate violations.
- One Dockerfile per image; every stage named; `final` is last. Banner each stage. In the runtime
  stage: `FROM`, `WORKDIR`, runtime packages, `COPY --from=build`, runtime `ENV`/`EXPOSE`/`VOLUME`,
  provenance, `LABEL`, `USER`, `ENTRYPOINT`/`CMD`. No commented-out instructions.
- Build stages normally use `--platform=$BUILDPLATFORM` and cross-compile. Native AOT instead uses
  explicit target-native builders (normally Linux amd64 and arm64), which can publish one multi-arch
  image without the `single-arch` profile; a RID alone is not a cross toolchain. `final` never has
  `--platform`. Declare target arguments late, map OS/architecture/variant in one failing-default
  `case`, and change the platform set everywhere at once.

## Inputs

- Never `latest` or untagged. Pin to the narrowest tag that still receives patches, name the
  distribution release, never build on a newer distribution than the runtime, and pin copied-tool
  images exactly. Digests only as `tag@sha256:…` with automated updates. Choose the smallest
  runtime that supports every platform; never `apt-get upgrade`.
- Copy manifests and lockfiles, resolve, then copy sources. Use cache mounts (`sharing=locked`
  unless read-only or self-locking) and `COPY --link` unless the destination crosses a symlink.
- Multi-command `RUN` steps are heredocs opening `set -eux` (no `-x` with secret mounts); one
  logical step per `RUN`; `apt-get` update, `--no-install-recommends` install and list cleanup in one
  step; no `-dev` packages at runtime; never pipe a download into a shell; absolute `WORKDIR`.
- Install from committed lockfiles in locked mode and keep every input deterministic except the
  floating base tag and distribution packages.

## Identity and Hardening

- .NET images start from the skill's canonical templates and pass `VERSION` and `GIT_COMMIT` to
  publish and to the tag and OCI labels; the
  [.NET artifact identity reference](../skills/containers-images/references/dotnet-artifact-identity.md)
  holds the contract.
- Choose managed versus Native AOT explicitly; `dotnet-aot` owns application compatibility, trimming
  and dependency checks. Select SDK, TFM and runtime inputs together; .NET 11 requires verified GA,
  actual tags and platform manifests, never guessed tags. AOT uses matching self-contained
  `PublishAot` restore/publish inputs, a builder-only native toolchain, compatible `runtime-deps`
  and a native executable entrypoint; retain provenance and select ICU/globalization deliberately.
  Cross-architecture AOT is opt-in only with a real target toolchain/sysroot and matching libc.
- Published images declare the provenance build arguments with safe defaults and set the OCI
  `title`, `description`, `source`, `licenses`, `version` and `revision` labels in one `LABEL`. Build
  arguments hold only public values.
- Run as an explicit non-root user; exec-form `ENTRYPOINT`/`CMD`; redeclare each `ARG` with a default
  in every stage that reads it. No credential in `ARG`, `ENV`, `COPY` or `LABEL`: use secret mounts
  at build time and orchestrator secrets at runtime.
- Design for a read-only root filesystem with writable paths created and owned in the image; listen
  above port 1024; never add `HEALTHCHECK`; leave no build toolchain in the runtime image.
- Every build context has an allow-list `.dockerignore` (`*` first, `!` entries, `/**`
  re-exclusions of build output), updated with the Dockerfile that starts reading a new file.

## Validation

- After a change, run the skill's audit, build and smoke-run the native platform, and leave the full
  matrix to CI. Run one image build at a time on a workstation.
