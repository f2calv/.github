---
description: 'Dockerfile, .dockerignore and Compose conventions — multi-architecture builds, stage structure, layer caching, provenance, image hardening, volume taxonomy.'
applyTo: '**/Dockerfile,**/Dockerfile.*,**/*.dockerfile,**/.dockerignore,**/docker-compose*.yml,**/docker-compose*.yaml,**/compose*.yml,**/compose*.yaml'
---

# Docker

These conventions describe a single-file, multi-architecture, cross-compiling image build. A
Dockerfile is expected to be readable as documentation, not merely executable as a recipe.

## File Header

- Start every Dockerfile with `# syntax=docker/dockerfile:1`. It opts the build into the latest
  stable frontend (heredocs, `COPY --parents`, `--mount`, build checks) regardless of the local
  Docker version, and floats on patch releases.
- Follow the syntax line with a comment block explaining what the file builds and why it is
  structured the way it is. Link to related repositories where they exist.
- Dockerfiles and the shell scripts they heredoc **must use LF line endings**. Enforce this in
  `.gitattributes`; a CRLF Dockerfile fails at build time with `/bin/sh: set: Illegal option -`.
- Use `# check=skip=<rule>` only for a rule that is deliberately violated, and comment why. Never
  blanket-skip. Prefer fixing the finding.
- New Dockerfiles must build clean under BuildKit checks. Treat every check warning as a defect to
  fix rather than noise to suppress.

## Stage Structure

- Keep one Dockerfile per image. **Never** add per-architecture Dockerfiles.
- Use exactly two meaningful stages, named `build` and `final`. Additional stages are permitted
  only where a tool must be pulled in as an image.
- Introduce each stage with a banner comment in this form:

  ```dockerfile
  # ------------------------------------------------------------------------------
  # Stage 1 of 2: build
  #
  # Why this stage is pinned/based/structured the way it is.
  # ------------------------------------------------------------------------------
  ```

- Within a stage, use `-- Section ---` sub-banners for the dependency layer, the compile layer and
  the provenance block, so the same landmark appears in every language.
- Order inside `final` is fixed: `FROM` → `WORKDIR` → runtime dependency `RUN` → `COPY --from=build`
  → runtime `ENV` → provenance `ARG`/`ENV` → `LABEL` → `USER` → `ENTRYPOINT`. The dependency install
  comes **before** the application copy so that editing source does not reinstall packages.

## Multi-Architecture Builds

- Pin the `build` stage to `--platform=$BUILDPLATFORM` and **cross-compile** to the target.
  Emulating the target under QEMU is typically 10-50x slower and is not an acceptable default.
- Never put a `--platform` override on the `final` stage. Leaving it unset lets buildx resolve the
  base image for `$TARGETPLATFORM`, so the resulting image is genuinely native.
- Declare `ARG TARGETARCH` / `ARG TARGETVARIANT` as late as possible — after every
  platform-agnostic layer — so dependency resolution is shared by all target legs.
- Concatenate the two into one flat token and switch on it. Keep the comment that documents the
  mapping:

  ```dockerfile
  # buildx injects TARGETARCH/TARGETVARIANT automatically:
  #   linux/amd64  -> TARGETARCH=amd64  TARGETVARIANT=
  #   linux/arm64  -> TARGETARCH=arm64  TARGETVARIANT=
  #   linux/arm/v7 -> TARGETARCH=arm    TARGETVARIANT=v7
  case "${TARGETARCH}${TARGETVARIANT}" in
      amd64) ... ;;
      arm64) ... ;;
      armv7) ... ;;
      *) echo "unsupported platform: linux/${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;;
  esac
  ```

- The `*)` arm is mandatory. An unrecognised platform must fail loudly at build time rather than
  silently produce an image for the wrong architecture.
- Resolve the platform mapping **once**. If more than one later stage needs it, write the result to
  a file and source it, rather than repeating the `case` statement.
- Treat the supported platform set as an explicit contract. Adding or dropping one is a deliberate
  change: update the `case`, the base-image choice, the build scripts, CI and the README together.
- Verify a base image publishes every supported platform before adopting it. Several distroless and
  vendor images have no 32-bit Arm manifest.

## Base Images

- Pin to the narrowest tag that still receives patch updates, such as a major or major.minor tag on
  a named distribution release. Never use `latest`.
- Pin an exact version for a tool image whose binary is copied into a build stage, because it is not
  covered by any lockfile.
- Do not pin a Dockerfile base image by digest. Floating on the patch tag is how base-image CVE
  fixes arrive; supply-chain integrity comes from `--pull`, attestations and a rebuild, not from
  freezing a digest.
- Prefer the smallest runtime that still supports every target platform and the application's actual
  framework needs, in this order: distroless/chiselled → slim → full.
- Document the rejected alternatives in a comment above the `final` stage, smallest to largest, with
  a one-line reason each was or was not chosen. That comment is the main reason someone reads the
  file.
- Choose the runtime image to match the framework the application actually publishes against, not
  the project type. A console application whose transitive dependencies pull in a web framework
  needs that framework's runtime image, or it fails at start-up with a missing-framework error.
- Never run a distribution-wide package upgrade (`apt-get upgrade`, `dist-upgrade` or equivalent).
  Pick up base-image patches by rebuilding on a refreshed base tag.

## Layer Caching

- Copy **only** the files that influence dependency resolution first (project and lock manifests),
  resolve dependencies, then `COPY` the sources. Editing a source file must not invalidate the
  dependency layer.
- The same rule governs the `final` stage: install runtime packages **before** copying build output.
  Layers are invalidated in sequence, so an install placed after the application copy is reinstalled
  on every source edit, and it cannot run in parallel with the build stage.
- Use `COPY --parents` to preserve directory structure when globbing manifests, rather than a
  flattening copy plus a fix-up `RUN`.
- Keep dependency resolution **before** `ARG TARGETARCH` whenever it is platform-agnostic, so one
  resolution is shared by every architecture leg.
- Use BuildKit cache mounts for package and compiler caches, always with `sharing=locked`:

  ```dockerfile
  RUN --mount=type=cache,target=/path/to/package/cache,sharing=locked \
      <resolve dependencies>
  ```

- Give architecture-specific compiler caches a per-architecture `id` (for example
  `id=build-cache-${TARGETARCH}${TARGETVARIANT}`) so the platform legs do not thrash a shared cache.
- A cache mount is **not** present in the resulting layer. Anything built into one must be copied out
  within the same `RUN` instruction.
- Prefer `COPY --link` for `COPY --from=build` into `final`; it produces an independently cacheable,
  rebasable layer. Do not use it where the destination path depends on a symlink or on content
  created by an earlier layer.

## RUN Instructions

- Use heredoc form for anything beyond a single command, and open it with `set -eux`:

  ```dockerfile
  RUN <<EOF
  set -eux
  ...
  EOF
  ```

  `-e` aborts on the first failure, `-u` catches an unset variable, `-x` puts the executed commands
  in the build log where a CI failure can be diagnosed.
- Without `set -e`, a heredoc reports success if only the last command succeeds. Never omit it.
- One logical step per `RUN`. Do not merge dependency resolution and compilation into one
  instruction — that destroys the cache split.
- Package installs must clean up in the **same** instruction, otherwise the removed files stay in
  the layer:

  ```dockerfile
  apt-get update
  apt-get install -y --no-install-recommends <packages>
  rm -rf /var/lib/apt/lists/*
  ```

- Always suppress recommended packages (`--no-install-recommends` or the equivalent). Always list
  packages explicitly; never install a meta-package to obtain one binary.
- A **temporary runtime debugging dependency** is legitimate and may be added to a `final` stage
  while an issue is being investigated. Keep it in one clearly-labelled block, and remove it once
  the investigation is done.
- A commented-out install block is held to the same standard as a live one. It must be correct,
  cleaned up and pinned, so that uncommenting it is the only edit required. A block that would fail,
  leak a package cache, or download an unpinned artifact is a defect even while commented out.
- Use absolute `WORKDIR` paths. Never `cd` between instructions — each `RUN` is a new shell.

## Reproducibility

- Install from a committed lockfile and fail on drift, using the toolchain's locked or
  hash-verified install mode. A build that silently resolves a newer dependency is a defect.
- Strip absolute paths and debug symbols from compiled binaries where the toolchain supports it.
- A build must produce the same image from the same commit on any machine. Nothing in the Dockerfile
  may read the host clock, the host network beyond pinned artifacts, or ambient host state.

## Provenance and Labels

- Every image carries the same flat provenance block in the `final` stage, each `ARG` with a safe
  default immediately followed by its `ENV`:

  ```dockerfile
  ARG GIT_REPOSITORY=n/a
  ENV GIT_REPOSITORY=$GIT_REPOSITORY
  ARG GIT_BRANCH=n/a
  ENV GIT_BRANCH=$GIT_BRANCH
  ARG GIT_COMMIT=n/a
  ENV GIT_COMMIT=$GIT_COMMIT
  ARG GIT_TAG=n/a
  ENV GIT_TAG=$GIT_TAG

  ARG GITHUB_WORKFLOW=n/a
  ENV GITHUB_WORKFLOW=$GITHUB_WORKFLOW
  ARG GITHUB_RUN_ID=0
  ENV GITHUB_RUN_ID=$GITHUB_RUN_ID
  ARG GITHUB_RUN_NUMBER=0
  ENV GITHUB_RUN_NUMBER=$GITHUB_RUN_NUMBER
  ```

  The defaults make the image buildable by hand; CI and the local build scripts supply real values.
- Declare OCI annotations as a single `LABEL` instruction with a link to the specification. Keep at
  least `title`, `description`, `source`, `licenses`, `version` and `revision`.
- An `ARG` value is visible in the image history. Provenance values are public by definition; nothing
  else belongs there.

## Runtime Hardening

- The final image runs as a **non-root** user. State it explicitly even when the base image already
  defaults to it — it documents the intent and survives a base-image change:
  - Where the base image documents an application UID, use that variable.
  - For distroless `:nonroot` tags, `USER nonroot:nonroot`.
  - Otherwise a numeric `USER 65532:65532`, which needs no `passwd` entry.
- Place `USER` after the last instruction that requires root, immediately before `ENTRYPOINT`.
- Use **exec form** for `ENTRYPOINT` and `CMD`. Shell form makes the application a child of
  `/bin/sh`, which does not forward `SIGTERM`, so the container is killed on timeout instead of
  shutting down cleanly.
- If a variable must be expanded at start-up, `exec` the real process so it becomes PID 1:
  `ENTRYPOINT ["sh", "-c", "exec <command> ${VAR}"]`. A bare `sh -c "<command>"` is a defect. This
  also requires a shell in the final image, which rules out distroless and chiselled — prefer a
  fixed entrypoint over a variable one.
- Never bake a secret into the image. No credential, token, connection string, key or certificate
  private key in `ARG`, `ENV`, `COPY` or a `LABEL`. Build-time secrets use
  `RUN --mount=type=secret,id=...`; runtime secrets are injected by the orchestrator.
- Only configuration with safe, non-sensitive defaults may be copied in, and every value in it must
  be overridable by an environment variable.
- Design for a read-only root filesystem: write only to an explicit `VOLUME` or a mounted path,
  never next to the application binaries.
- `EXPOSE` is documentation only and does not publish anything. Use ports above 1024, because a
  non-root user cannot bind a privileged port.
- Do not add `HEALTHCHECK` for images destined for Kubernetes — it is ignored there, and liveness
  and readiness belong in the chart. Add one only where Compose is the deployment target.
- Do not leave a compiler, SDK or build toolchain in the final image. If the runtime needs a build
  tool, that is a design problem to solve in the build stage.
- An interpreted-language runtime that inherently ships its own package manager is exempt, provided
  the smallest maintained runtime supporting every target platform was chosen. Note the exemption in
  the `final` stage comment.

## .dockerignore

- Every repository with a Dockerfile has a `.dockerignore`.
- Use the deny-everything-then-allow form. An allowlist keeps the context minimal, speeds up the
  build, and stops an unrelated edit (docs, charts, IDE state, `.git`) invalidating cached layers:

  ```gitignore
  # Deny everything, then explicitly allow only what the build needs.
  *

  !src/**
  ```

- The allowlist is also a security boundary: it is what stops a local secrets file, a `.env`, a key,
  or an untracked scratch file being uploaded into the build context.
- When a Dockerfile starts consuming a new file, update `.dockerignore` in the same change.

## Building

- Local builds go through the repository's build scripts, which mirror the image job in CI and
  derive every value from git. Keep the shell and PowerShell variants in step with each other and
  with their counterparts in sibling repositories.
- A multi-platform image cannot be loaded into the local image store. A local build targets one
  platform with `--load`; exercising every platform requires `--output=type=oci,dest=...` or a push.
- Always pass `--pull` so a stale local base image cannot mask a broken build.
- Push builds publish attestations: `--provenance=mode=max --sbom=true`.
- Registry, repository and tag values must be lowercase.
- Build the image after any change to the Dockerfile or to packaging, and validate each declared
  platform before claiming multi-architecture support.

## Compose

Compose describes the **local development and demo environment**. It is never the deployment target.
A Compose file therefore optimises for "clone and run", not for production fidelity.

- One `docker-compose.yml` per repository, in the root. Do not split into
  `docker-compose.override.yml` or per-environment files; use profiles instead.
- Never include the obsolete top-level `version:` key. Modern Compose warns on it.
- Start the file with a header comment block listing, in order: what the default `docker compose up`
  starts, each profile and its command, and the published endpoints. The header is the first thing a
  new contributor reads — keep it accurate.

### Volume Taxonomy

This is the rule that matters most, because getting it wrong silently pollutes the repository with
runtime state.

- **Tracked configuration** a container reads lives in a dedicated tracked directory and is
  bind-mounted **read-only**:

  ```yaml
  volumes:
    - ./.docker/service.conf:/etc/service/service.conf:ro
  ```

- **Volatile or regenerable data** (databases, caches, emulator state, downloaded artifacts) uses a
  **named volume**, never a bind mount:

  ```yaml
  volumes:
    - database_data:/var/lib/database
  ```

- **Host fixtures** the application only reads (sample media, test inputs) are bind-mounted
  read-only from a gitignored directory.
- A container must **never** be able to write into the repository working tree. Every bind mount is
  `:ro` unless there is a written reason it cannot be, and that reason belongs in a comment next to
  the mount. Services that persist their own settings will otherwise rewrite tracked files or drop
  runtime state into the configuration directory.
- Prefer an explicit relative path over a variable default that widens the mount. A default such as
  `${SOME_DIR:-.}` mounts the entire repository; scope it to a subdirectory.
- Name volumes `snake_case`, prefixed with the owning service. Never a bare `data`.

### The Configuration Directory Is Allow-Listed

The tracked configuration directory holds configuration only, and `.gitignore` enforces that with
the same deny-everything-then-allow form used by `.dockerignore`:

```gitignore
.docker/*
!.docker/service.conf
```

- Add the `!` entry in the **same change** as the Compose mount that consumes the file. A
  mounted-but-unlisted file survives only until someone re-clones or re-adds it.
- Never widen the deny rule to silence runtime droppings. If a service writes into the configuration
  directory, the mount is wrong — move that path to a named volume.

### Images

- **Pin every image**, exactly as `FROM` is pinned. A floating tag in Compose is how a bug you
  already pinned away from elsewhere gets back in.
- Pin to the narrowest tag that still receives patch updates, matching the base-image rule.
- Untagged means `latest`, so an untagged `image:` is a defect, not a shorthand.
- Where upstream publishes no versioned tag, pin by digest and say why in a comment. This is the one
  place a digest pin is correct; it is the only immutable reference available.
- Where upstream explicitly supports only `latest`, pin the newest version-specific tag anyway and
  record the upstream position in a comment, so the exception is a decision rather than an oversight.
- Keep an image used both locally and in the cluster on the **same version** in Compose and in the
  chart. The point of running it locally is to exercise what production runs.

### Service Dependencies

- Give every service a `healthcheck` when another service depends on it, or when "is it ready yet?"
  is a question a developer would otherwise answer by staring at logs.
- Depend on readiness, not start order:

  ```yaml
  depends_on:
    database:
      condition: service_healthy
  ```

  Bare `depends_on: [x]` only orders container start; the dependent service will race a slow
  first-run download or migration.
- One-shot initialisation containers use `restart: "no"`; long-lived services use
  `restart: unless-stopped`.

### Profiles

- The default `docker compose up` starts **infrastructure only**. The application under development
  runs from the IDE or the local run command against it.
- Anything that builds from source, needs a GPU, pulls a large model, or exists only for a demo goes
  behind a named profile, documented in the header comment.
- Name profiles for what they deliver (`demo`, `harness`), not for what they contain.

### Secrets

- Only well-known public development constants may appear inline, such as an emulator's published
  default key or a local database password. Nothing that would matter if the repository were public.
- Real values come from a gitignored mount or `env_file`, with a safe default so a clone still
  starts:

  ```yaml
  - ${USER_SECRETS_DIR:-./.secrets}:/path/in/container:ro
  ```

- Never commit a `.env`. Add it to `.gitignore` alongside the secrets directory.

### Dead Configuration

Commented-out services and volumes are dead code and are deleted, not parked. Git history is the
archive. A Compose file whose bulk is commented out no longer documents anything.
