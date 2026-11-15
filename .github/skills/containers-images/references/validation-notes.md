# Validation Notes

Practical limits and checks when validating an image locally, after the audit and native build.

* Run one image build at a time on a workstation, and build the full platform matrix only when the
  change is platform-specific; CI builds every platform. Measured on a Windows laptop with Docker
  Desktop in September 2026, a three-platform build took about 20 seconds for the .NET sample and
  12 minutes for the Rust sample, and parallel multi-platform builds forced a reboot.
* A service that needs deployment configuration, such as a mounted certificate, exits at start-up in
  a bare `docker run`. That still proves the image starts and reads its configuration; confirm the
  failure names the missing input.
* `--pull` stops a stale local base image masking a broken build.
* Native AOT needs native builders for each declared target, normally Linux amd64 and arm64.
  The template intentionally fails if build and target platforms differ; a single amd64 workstation
  is not proof of arm64 support. Audit output cannot verify a linker, sysroot, libc or executable.
  Recheck [version/tag/platform evidence](dotnet-version-inputs.md) before changing version inputs.
* A `--version` smoke test must compare exactly with the effective `VERSION` build argument.
  If CI lowercases image tags and uses that tag as `VERSION`, normalize the expected prerelease
  label too; raw GitVersion output can differ in case. Exercise both preview and clean versions.
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
* Use the `containers-workflows` skill for the repository's scripted local builds.

## Windows Without Docker

WSL Containers (WSLC) offers a Windows-local container path without Docker Desktop or a Docker
daemon. Verify availability in the installed WSL release rather than assuming that any WSL
installation includes it. Microsoft's [WSLC prerequisites](https://github.com/microsoft/WSL/blob/master/nuget/Microsoft.WSL.Containers/docs/README.MD#prerequisites)
describe installation without a Linux distribution; obtain approval before installing or updating
WSL and respect workstation policy. Do not start Docker Desktop as an automatic fallback.

Discover the executable, then inspect its version and help only if present:

```powershell
Get-Command wslc -ErrorAction SilentlyContinue
```

```powershell
wslc --version
wslc build --help
wslc run --help
```

The upstream [command registration](https://github.com/microsoft/WSL/blob/master/src/windows/wslc/commands/RootCommand.cpp)
includes `build`, `run`, `info`, `logs` and `stop`. Use the installed command-specific help as the
contract: current source is not proof of a released CLI's options or minimum WSL version.

* Reuse the repository's Dockerfile and `.dockerignore`, version inputs and image profile. Do not
  create weaker per-runtime or per-.NET-major templates to make a local build pass.
* Before building, check support for the features actually used: multi-stage targets, automatic
  platform arguments, `COPY --parents` / `--exclude`, cache mounts and secret mounts. Never replace
  unsupported secret mounts with credentials in build arguments or copied configuration.
* With build/run approval, build the native host platform using `wslc build`, then smoke-run with
  `wslc run`. Confirm port-mapping syntax and bind service ports to `127.0.0.1`; retain the image's
  non-root user. Check the expected endpoint or process exit, inspect `wslc logs` when needed,
  then stop and remove only the container created for that validation using the installed help.
  Tests still require separate consent.
* Record the WSLC version, platform and checks performed. A successful local build/run does not
  prove Buildx `--check`, other architectures, Compose, registry/image-store interoperability,
  provenance or SBOM support. Report unavailable checks as gaps, not passes; keep the existing
  Docker/Buildx CI and publication scripts unchanged unless explicitly adapting them.
