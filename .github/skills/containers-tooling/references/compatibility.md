# Container Tool Capabilities

Separate the application contract from the engine/provider/builder combination used to verify it.
Upstream documentation is a starting point, not runtime evidence for a particular workstation.

## Capability Matrix

| Surface | Docker path | Podman path | Required evidence |
| --- | --- | --- | --- |
| Linux containers on Windows | Desktop Linux backend or another approved Linux engine | Managed WSL2/Hyper-V machine | Selected endpoint, host/server versions and platform |
| Compose | Docker Compose provider | `podman compose` plus an external provider | Provider/version, flags, expected service selection and runtime results |
| Image builds | BuildKit/Buildx | Buildah-backed `podman build`, or a separately approved builder | Actual Dockerfile features and output contract |
| Buildx | Full CLI with its supported driver/backend | `podman buildx build` is a partial alias | Never assume builder create/inspect, checks or exporters are supported |
| Dev Containers | Documented Docker path | Podman 5+ CLI integration documented by VS Code | Rebuild, non-root mount behavior and nested access separately |
| NVIDIA on Windows | Supported engine/backend/toolkit combination | [WSL2 plus toolkit/CDI setup](setup.md#nvidia-gpu-on-wsl2) | Device visibility and a real workload; not Hyper-V parity |
| Publication | Existing CI's platform/digest/attestation contract | Only the capabilities actually verified | Registry manifest/index digest, platforms and required metadata |

WSLC's SDK lists x64 and ARM64 as supported host platforms; that is not proof of x64-to-ARM64
cross-building. Check installed `wslc build --help` for target-platform selection. If it exposes no
such option, report foreign-platform builds as unverified. Language-level cross-compilation can
produce ARM64 binaries without executing them, but does not establish ARM64 image assembly,
emulation, native AOT toolchains or multi-platform index publication. Keep the proven CI path for
those requirements.

Podman supports Dockerfiles, but the syntax directive does not make its builder BuildKit.
Check automatic platform arguments, heredocs, `COPY --link`/`--parents`/`--exclude`, cache/secret
mounts and stage selection against installed versions. Never substitute build arguments or copied
credential files for unsupported secret mounts.

The shared workflows may require BuildKit even when Podman runs local dependencies.
Keep that limitation explicit until an approved builder path is verified. Do not weaken Dockerfiles,
image hardening, caching or CI checks merely to claim tool agnosticism.

## Verification

1. Record OS/platform, engine connection/context, provider and builder versions. Inspect pre-existing
   workloads without dumping environments, resolved Compose configuration or registry credentials.
2. Validate the effective model for the default and each supported profile/combination. Check the
   expected services. Empty defaults and explicitly selected one-shot services can be intentional.
3. With runtime approval, start the smallest dependency stack and verify health plus protocol
   connectivity from the intended client. Container-to-container DNS and Windows-host connectivity
   are different tests.
4. Verify read-only binds, file/directory existence, Windows path translation and named-volume
   ownership under the chosen rootless/rootful mode. Existing data in another engine is not proof
   the selected volume is populated.
5. Test initializer exit status and dependency gating. Profile parsing alone does not prove optional
   dependencies, `env_file.required`, `--wait` or one-shot completion semantics.
6. With build approval, exercise representative native Release/Debug images and their actual
   version/metadata/entrypoints. Test stages still require test consent. Verify the resulting image
   is visible to the same engine Compose uses.
7. Test cache-only, local-load/run and push behavior separately where supported. Podman placing an
   image in its store is not equivalent to a Buildx cache-only result. Multi-platform and
   attestation checks remain separate gates.
8. Stop only task-started services when checks finish. Preserve volumes and account registrations.
   Never interpret a missing executable, skipped test or unsupported capability as success.

Short image names can trigger Podman's registry-selection prompts. Prefer a verified fully
qualified registry reference for unattended commands; preserve the intended image/version.
Check local image naming and pull policy before changing a built service to a registry image.

### Foreign-Architecture Checks

Inspect existing emulation before installing or registering anything. A failing machine-shell
`binfmt_misc` listing does not prove rootless container execution fails; probe the actual namespace.
Privileged registration can affect other distributions sharing the WSL kernel, so require explicit
approval and never flush registrations as a diagnostic shortcut.

Build one target at a time. Exercise a real foreign-platform `RUN`, verify automatic target
arguments, inspect the stored image's OS/architecture and exposed variant metadata, then run its
entrypoint as non-root and check the actual architecture. Image assembly without execution is a
different result. Successful emulation establishes neither native AOT readiness nor acceptable
application performance, multi-platform index publication or support in the shared build adapter.

## CI Boundary

Local runtime selection does not change remote GitHub Actions runners. Keep Docker/BuildKit
workflows, action IDs, Dependabot ecosystems and publication guarantees unchanged unless explicitly
adapting those surfaces. Check self-hosted runner prerequisites separately.

Do not promise an arbitrary remote builder solves local `--load`: verify export/import format,
target engine store, credentials and digest identity. Require authenticated transport for exposed
builder/API endpoints.

## Official References

* [Podman build and Buildx alias](https://docs.podman.io/en/latest/markdown/podman-build.1.html)
* [Compose provider selection](https://docs.podman.io/en/latest/markdown/podman-compose.1.html)
* [Podman short names](https://docs.podman.io/en/latest/markdown/podman-pull.1.html)
* [VS Code alternate engines](https://code.visualstudio.com/remote/advancedcontainers/docker-options)
* [Windows GPU access](https://podman-desktop.io/docs/podman/gpu)
* [Buildx remote driver](https://docs.docker.com/build/builders/drivers/remote/)
