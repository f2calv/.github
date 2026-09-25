# Container Image Options

Decision tables for choices that vary per image. Record the chosen option, and the rejected ones
where the reason is not obvious, in the Dockerfile's header or stage banner.

## Workload Shape

Declare a shape other than `service` in the header comment as `# Shape: job` or `# Shape: tool`.

| Concern | `service` | `job` | `tool` |
| --- | --- | --- | --- |
| Started by | Kubernetes Deployment or StatefulSet | Kubernetes Job, CronJob or init container | `docker run --rm` on a workstation or in a CI step |
| Entrypoint | Server binary, no default arguments | Task binary | Program binary; default arguments, if any, in `CMD` |
| Ports | `EXPOSE` each listener (8080 HTTP, 5001 gRPC for .NET) | None | None |
| Input | Configuration and injected secrets | Configuration and injected secrets | Arguments, environment variables, `--env-file`, mounted files |
| Output | Logs to stdout | Logs to stdout; exit code | Product to stdout or a mounted directory; diagnostics to stderr; exit code |
| Writable paths | State and cache directories owned by the runtime user | Same as service | A `VOLUME` owned by the runtime user, plus `--user "$(id -u):$(id -g)"` documented for bind mounts |
| Interactivity | None | Never prompt | Never prompt without a TTY; offer a flag that skips each prompt |
| Validation | Smoke-run until it logs start-up, then stop it cleanly | Run to completion and check the exit code | Run `--version` or `--help` in CI before publishing |
| Floating tag | Deployments pin an exact version | Deployments pin an exact version | A convenience `latest` tag is common; automation still pins an exact version |

A tool can be distributed both as an image and as a native package, such as a .NET global tool.
Keep the image's entrypoint and arguments identical to the native command so the documentation
serves both.

## Build Strategy

| Strategy | Use when | Shape |
| --- | --- | --- |
| Cross-compile (default for compiled languages) | The toolchain can target other architectures: Go, Rust, C and C++ with a cross toolchain, .NET RID-specific publish | `build` on `$BUILDPLATFORM`; map the target in one `case` |
| Architecture-neutral | The output runs on every target unchanged: pure-Python wheels, .NET IL, JVM bytecode | `build` on `$BUILDPLATFORM`; the `case` only validates the platform |
| Native per target (`single-arch` profile) | The build executes target-architecture tools, or tunes for one CPU | No `$BUILDPLATFORM` pin; one declared platform; the header explains why |

## Platform Set

- The default set is `linux/amd64`, `linux/arm64` and `linux/arm/v7`. Drop a platform when a
  required base image or native dependency does not publish it, and say which one in the header.
- A platform change touches the `case`, the base images, the build scripts, CI and the README in
  the same change.
- Check what a base image publishes before relying on it:

  ```bash
  docker buildx imagetools inspect <image> --format '{{range .Manifest.Manifests}}{{.Platform.Architecture}}{{.Platform.Variant}} {{end}}'
  ```

## Runtime Base

Platforms below were confirmed with `docker buildx imagetools inspect` in September 2026. Re-check
before adopting, because publishers add and retire platforms.

| Ecosystem | Smallest suitable runtime | amd64 / arm64 / arm/v7 | Notes |
| --- | --- | --- | --- |
| .NET | `mcr.microsoft.com/dotnet/runtime:10.0-noble-chiseled` | Yes / Yes / Yes | No shell or package manager. The `10.0` tags are Ubuntu 24.04, not Debian |
| ASP.NET Core | `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` | Yes / Yes / Yes | Also needed by console apps whose dependencies carry a `FrameworkReference` to `Microsoft.AspNetCore.App` |
| Go, `CGO_ENABLED=0` | `gcr.io/distroless/static-debian13:nonroot` | Yes / Yes / Yes | CA certificates, tzdata and a non-root user |
| Rust `*-linux-gnu` | `gcr.io/distroless/cc-debian13:nonroot` | Yes / Yes / Yes | glibc and libgcc; build on Debian 13 or older |
| Rust `*-linux-musl` | `gcr.io/distroless/static-debian13:nonroot` | Yes / Yes / Yes | Fully static binaries only |
| Python | `python:3.14-slim-trixie` | Yes / Yes / Yes | `gcr.io/distroless/python3-*` publishes amd64 and arm64 only |

Move up to a larger base only for a stated need: a shell for a start-up script, an apt-installed
native library, or a debugging session. The distroless `-debian12` images are past their support
window; use `-debian13`.

## Pinning

| Mode | Example | Use for |
| --- | --- | --- |
| Minor tag (default) | `mcr.microsoft.com/dotnet/sdk:10.0`, `python:3.14-slim-trixie` | Runtimes and SDKs whose minor releases can change behaviour |
| Major tag | `golang:1-trixie`, `rust:1-trixie` | Build-stage toolchains with strong compatibility guarantees |
| Exact version | `ghcr.io/astral-sh/uv:<x.y.z>` | Images that only supply a copied tool |
| Tag and digest | `python:3.14-slim-trixie@sha256:<digest>` | Byte-for-byte rebuilds; requires Dependabot's `docker` ecosystem to raise update pull requests |
| Vendor commit tag (`vendor` profile) | `example.com/vendor/image:main-<commit>` | Rebuilding a vendor image from an exact upstream revision |

## Cache Mount Sharing

Every platform leg of a multi-platform build mounts the same cache id. `sharing=locked` admits one
leg at a time, which serialises those steps but cannot corrupt the cache. `shared` lets the legs run
concurrently, which is safe when the step only reads the cache, or when the tool coordinates through
a lock file inside the mounted directory. Each build container has its own `/tmp` and its own view of
paths outside the mount, so a lock kept there is invisible to the other legs. Default to `locked`.

| Cache | Target | Sharing | Reason |
| --- | --- | --- | --- |
| apt | `/var/cache/apt`, `/var/lib/apt` | `locked` | apt fails rather than waits on its lock |
| NuGet | `/root/.nuget/packages` | `locked` | On Linux NuGet keeps its restore locks under the temporary directory, outside the mount |
| Go modules | `/go/pkg/mod` | `shared` | `go` locks inside the module cache itself |
| Go build | `/root/.cache/go-build` | `locked` | Per-platform `id`, so the lock costs nothing |
| cargo registry and git | `/usr/local/cargo/registry`, `/usr/local/cargo/git` | `locked` | cargo's `.package-cache` lock sits in `CARGO_HOME`, outside these mounts |
| cargo target | `/src/target` | `locked` | Per-platform `id` |
| uv | `/root/.cache/uv` | `shared` | uv locks inside its cache directory |
| Anything else | | `locked` | Until the tool is shown to lock inside the mounted directory |

The NuGet and cargo reasons come from how each tool places its lock files. The concurrent-write
failure has not been reproduced here. Earlier Dockerfiles in these repositories adopted `locked`
for NuGet after restore problems on multi-platform builds; the cause was never recorded.

## Provenance

| Mode | Use when | Shape |
| --- | --- | --- |
| Build arguments, environment and labels (default) | The application reports its build at runtime | Each `ARG` with a default, followed by its `ENV`; labels reference the arguments |
| Build arguments and labels | Nothing inside the image reads the values, such as a `vendor` rebuild | `ARG` with defaults; labels only |
| None | `debug` and `sample` profiles | Omit the block |

Attestations (`--provenance=mode=max --sbom=true`) are set by the build workflow, not the
Dockerfile. When a registry takes a multi-architecture image's description from the index, pass
`--annotation index:org.opencontainers.image.description=<text>` as well as the label.

## Entrypoint

| Case | Pattern |
| --- | --- |
| Fixed command (default) | `ENTRYPOINT ["/app/<binary>"]` or `ENTRYPOINT ["dotnet", "<assembly>.dll"]` |
| Command chosen by a build argument | Resolve it in the build stage into a fixed-name link, then `ENTRYPOINT ["/app/entrypoint"]` |
| Command needs start-up expansion | `ENTRYPOINT ["sh", "-c", "exec <command> ${VAR}"]`; the image needs a shell |

## Debug Variants

| Need | Pattern |
| --- | --- |
| Extra tooling in the same image | An optional `debug` target derived from the runtime stage; `final` stays last |
| Different build inputs, such as sibling source trees instead of packages | `Dockerfile.Debug` with its own `Dockerfile.Debug.dockerignore`, so the shared `.dockerignore` stays narrow |
| One-off investigation | A local, uncommitted `debug` target |

`Dockerfile.Debug` is never published. The build scripts in the `container-workflows` skill select
it for Debug builds and discover its sibling repositories from its `COPY deps/...` lines.

## Test Stage

An optional `test` stage runs a repository's tests in the SDK image, so a contributor can run them
without installing the toolchain. `final` does not depend on it, so the default build and CI never
execute it; it runs only with `docker buildx build --target test`.

| Question | Default |
| --- | --- |
| Add one? | Only when the repository has tests that need no credentials, services or hardware. CI's own test job stays the gate |
| Which tests? | Credential-free only: filter out the integration category, for example `--filter-not-trait "Category=Integration"` |
| Network? | `RUN --network=none` after an up-front restore, so a hidden external dependency fails instead of passing by luck |
| Platform? | `$BUILDPLATFORM`: test assemblies for interpreted or IL-compiled languages are architecture-neutral |
| Frameworks? | Only those the SDK image ships a runtime for; a multi-targeted .NET test project passes `--framework` |
| Context? | Keep tests in `.dockerignore`, and `COPY --exclude` them in the build stages so a test edit never busts the publish cache |
| Results? | Read the `--progress=plain` log; a failing test fails the build. Export files only when a tool needs them |

Integration tests that need a database, emulator or credential belong in Compose or on the host,
never in a Dockerfile: a build step has no service dependencies and must never receive a real
credential. Running `--target test` still runs tests, so ask before running it.

## Writable Paths

| Base | Pattern |
| --- | --- |
| Has a shell | `RUN install -d -o <uid> -g <gid> /var/lib/app` before `USER` |
| Chiselled or distroless | Create the directory in `build` and copy it with `COPY --link --from=build --chown=<uid>:<gid>` |

Declare `VOLUME` for a path only after it exists with the right owner; otherwise an anonymous volume
is created root-owned and the non-root process cannot write to it.
