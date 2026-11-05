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
