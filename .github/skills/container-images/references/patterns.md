# Container Image Patterns

Copy-ready fragments for the conventions in `docker.instructions.md`. The public
`multi-arch-container-dotnet`, `-go`, `-rust` and `-python` repositories under the `f2calv` GitHub
account are complete reference implementations that follow these patterns stage for stage.

## Header and Stage Banners

```dockerfile
# syntax=docker/dockerfile:1
#
# <What the image is, and why it is structured this way.>
# Profile: single-arch   <- only when not published

# ------------------------------------------------------------------------------
# Stage 1 of 2: build
#
# Why this stage is based, pinned and structured the way it is.
# ------------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM <image>:<tag> AS build

# -- Dependency layer ----------------------------------------------------------
# -- Compile layer -------------------------------------------------------------
# -- Provenance ----------------------------------------------------------------
```

## Platform Mapping

```dockerfile
# buildx injects TARGETARCH/TARGETVARIANT automatically:
#   linux/amd64  -> TARGETARCH=amd64  TARGETVARIANT=
#   linux/arm64  -> TARGETARCH=arm64  TARGETVARIANT=
#   linux/arm/v7 -> TARGETARCH=arm    TARGETVARIANT=v7
ARG TARGETARCH
ARG TARGETVARIANT
RUN <<EOF
set -eux
case "${TARGETARCH}${TARGETVARIANT}" in
    amd64) RID=linux-x64   ;;
    arm64) RID=linux-arm64 ;;
    armv7) RID=linux-arm   ;;
    *) echo "unsupported platform: linux/${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;;
esac
EOF
```

When several instructions need the mapping, resolve it once and source the result:

```dockerfile
RUN <<EOF
set -eux
case "${TARGETARCH}${TARGETVARIANT}" in
    amd64) TARGET=x86_64-unknown-linux-gnu ;;
    arm64) TARGET=aarch64-unknown-linux-gnu ;;
    armv7) TARGET=armv7-unknown-linux-gnueabihf ;;
    *) echo "unsupported platform: linux/${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;;
esac
echo "export CARGO_BUILD_TARGET=$TARGET" > /etc/build-target.env
EOF

RUN <<EOF
set -eux
. /etc/build-target.env
cargo build --locked --release --target "$CARGO_BUILD_TARGET"
EOF
```

## .NET

Restore every runtime identifier once, before `TARGETARCH`, then publish offline per platform. A
RID-specific publish otherwise restores again in every platform leg. Pass the list with escaped
quotes: MSBuild reads `%3B` as a literal semicolon, which yields one invalid identifier.

```dockerfile
COPY --parents Directory.Build.props Directory.Packages.props src/**/*.csproj ./
RUN --mount=type=cache,target=/root/.nuget/packages,sharing=shared \
    dotnet restore "src/$APP_NAME/$APP_NAME.csproj" \
        "-p:RuntimeIdentifiers=\"linux-x64;linux-arm64;linux-arm\""

COPY . .
ARG TARGETARCH
ARG TARGETVARIANT
RUN --network=none --mount=type=cache,target=/root/.nuget/packages,sharing=shared <<EOF
set -eux
case "${TARGETARCH}${TARGETVARIANT}" in
    amd64) RID=linux-x64   ;;
    arm64) RID=linux-arm64 ;;
    armv7) RID=linux-arm   ;;
    *) echo "unsupported platform: linux/${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;;
esac
dotnet publish "src/$APP_NAME/$APP_NAME.csproj" --configuration Release --runtime "$RID" \
    --self-contained false --no-restore --output /out
ln -s "$APP_NAME" /out/entrypoint
EOF
```

- `--network=none` proves the publish step no longer reaches NuGet.
- The SDK writes the target assembly name into the apphost, so the fixed-name `entrypoint` link
  starts the right application. Use `ENTRYPOINT ["/app/entrypoint"]`; it works on chiselled images
  because it needs no shell.
- Add `packages.lock.json` (`RestorePackagesWithLockFile`) and restore with `--locked-mode` to make
  dependency drift fail the build.

Verified in September 2026 with the .NET 10.0.401 SDK: a three-platform build succeeded, and the
amd64 and arm/v7 images started through the link and exited cleanly on `SIGTERM`.

## Go

```dockerfile
RUN --mount=type=cache,target=/go/pkg/mod,sharing=shared \
    --mount=type=cache,target=/root/.cache/go-build,id=go-build-${TARGETARCH}${TARGETVARIANT},sharing=locked <<EOF
set -eux
case "${TARGETARCH}${TARGETVARIANT}" in
    amd64) export GOARCH=amd64 ;;
    arm64) export GOARCH=arm64 ;;
    armv7) export GOARCH=arm GOARM=7 ;;
    *) echo "unsupported platform: linux/${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;;
esac
export CGO_ENABLED=0 GOOS=linux
go build -trimpath -ldflags "-s -w" -o "/out/${APP_NAME}" "./src/${APP_NAME}"
EOF
```

## Rust

- Install the cross linker (`g++-<triple>`, `libc6-dev-<arch>-cross`) and `rustup target add` in one
  platform-specific step, then write the cargo linker variables to the sourced environment file.
- `cargo fetch --locked` needs a target; stub `src/main.rs` in the dependency layer and let the real
  sources overwrite it.
- Keep `target/` in a per-platform cache mount and `install` the binary out of it in the same `RUN`.
- Set `strip = true` in the release profile when symbols are not needed for crash analysis.

## Python

- Export the lockfile (`uv export --locked --no-dev`) and install with `pip --require-hashes
  --only-binary :all: --platform any --abi none --implementation py` to prove every dependency is a
  universal wheel. One resolution then serves every platform with no emulation.
- Set `PYTHONDONTWRITEBYTECODE=1` and `PYTHONUNBUFFERED=1` in the runtime stage.

## apt

Default form, when the stage runs rarely:

```dockerfile
RUN <<EOF
set -eux
apt-get update
apt-get install -y --no-install-recommends <packages>
rm -rf /var/lib/apt/lists/*
EOF
```

Cached form, for build stages rebuilt often. The cache mounts keep package lists and archives out of
the layer; the base image's `docker-clean` hook would otherwise delete the archives:

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOF
set -eux
rm -f /etc/apt/apt.conf.d/docker-clean
apt-get update
apt-get install -y --no-install-recommends <packages>
EOF
```

## Provenance and Labels

```dockerfile
# -- Provenance ----------------------------------------------------------------
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

# https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL org.opencontainers.image.title="<name>" \
    org.opencontainers.image.description="<one line>" \
    org.opencontainers.image.source="https://github.com/<owner>/<repository>" \
    org.opencontainers.image.licenses="<SPDX identifier>" \
    org.opencontainers.image.version="$GIT_TAG" \
    org.opencontainers.image.revision="$GIT_COMMIT"
```

Drop the `ENV` lines when nothing in the image reads the values.

## Optional Debug Target

`final` stays the last stage, so default builds and CI are unchanged. Build the variant with
`docker buildx build --target debug`.

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --link --from=build /out .
# ...runtime ENV, provenance, LABEL...
USER $APP_UID
ENTRYPOINT ["/app/entrypoint"]

# Investigation tooling only; never published.
FROM runtime AS debug
USER root
RUN <<EOF
set -eux
apt-get update
apt-get install -y --no-install-recommends curl iputils-ping
rm -rf /var/lib/apt/lists/*
EOF
USER $APP_UID

FROM runtime AS final
```

A chiselled or distroless runtime has no package manager. Base `debug` on the full variant of the
same image instead, and copy the published output into it.

## Writable Directory on a Chiselled Base

```dockerfile
# build stage
RUN install -d /out/state

# final stage
COPY --link --from=build --chown=$APP_UID:$APP_UID /out/state /var/lib/app
```

## Build-Time Secret

```dockerfile
RUN --mount=type=secret,id=feed_token,env=FEED_TOKEN <<EOF
set -eu
curl -fsSL -H "Authorization: Bearer $FEED_TOKEN" -o /tmp/package.tgz \
    "https://example.com/packages/example-1.2.3.tgz"
tar -xzf /tmp/package.tgz -C /opt
rm -f /tmp/package.tgz
EOF
```

`set -eu` omits `-x` so the token never reaches the build log. Never let a tool persist the secret,
for example a package manager writing it into a configuration file inside the layer.
