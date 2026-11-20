# Container Tool Setup

Use approved software sources and record versions. Open-source licensing does not establish approval
under an organization's software policy.

## Docker Desktop

1. Download the installer for the host OS from the
   [official Docker Desktop download page](https://www.docker.com/products/docker-desktop/).
2. With approval, install it and follow its onboarding/prerequisite prompts. Confirm that the
   [Desktop licensing terms](https://docs.docker.com/subscription-billing/desktop-license/) fit the use.
3. Start Desktop when permitted. Verify `docker --version`, `docker compose version`, then
   `docker version` and the selected context before running repository workloads.

No separate Compose installation is normally needed: Desktop bundles it. Do not automatically
change Windows virtualization, registry credentials or an existing Docker context during setup.

## Podman

Podman is the container engine/CLI. Podman Desktop is an optional UI that can help install the
engine and Compose provider; installing the UI alone does not prove either is ready.
Use the [official installation guide](https://podman.io/docs/installation) and
[Windows setup guide](https://podman-desktop.io/docs/installation/windows-install).

### Install the Engine

On Windows, verify the approved package before installation:

```powershell
winget show --id RedHat.Podman --exact --source winget
winget install --id RedHat.Podman --exact --source winget
```

Alternatively, download the official installer. If a UI is wanted, use the official
[Podman Desktop download](https://podman-desktop.io/downloads) and follow its engine onboarding.
Obtain approval before enabling WSL2/Hyper-V, updating WSL or rebooting. Do not install an additional
Linux distribution merely because a generic WSL tutorial does so.

On Linux, use the distribution-supported Podman package. On macOS, follow the official installation
guide and create a managed Linux machine. Windows/macOS container engines run inside a Linux VM;
rootless operation does not remove that requirement.

### Create and Verify a Windows Machine

First inspect existing machines and connections:

```powershell
podman --version
podman machine list
podman system connection list
podman machine info
```

If none is suitable, with approval create a named machine using an approved provider:

```powershell
podman machine init example-machine
podman machine start example-machine
podman info
podman machine inspect example-machine
```

Confirm the provider reported by `machine info` before initialization. Provider-selection options
vary by release; do not assume `machine init --provider` exists merely because newer documentation
lists it. Use the installed help and official setup guide when a different provider is required.
WSL resource limits are not
interchangeable with QEMU options. Start rootless where workable; rootful mode is a separate,
approved compatibility decision, not a generic permission fix.
Verify host/client/server versions and the selected connection. Do not dump full inspection output
into public artifacts; it can contain workstation paths and identities.

### Install and Select Compose Independently

`podman compose` wraps an external provider. Use the
[Podman Desktop Compose setup](https://podman-desktop.io/docs/compose/setting-up-compose), or an
approved independently downloaded binary from the
[Docker Compose releases](https://github.com/docker/compose/releases). Verify release checksums and
put it in an approved user tool directory; do not rely on Desktop's installation directory.

Docker Compose is [Apache-2.0 licensed](https://github.com/docker/compose/blob/main/LICENSE).
A modern executable named `docker-compose` is not necessarily the retired Python Compose V1.
The Python `podman-compose` implementation is another provider, not an interchangeable version
of Docker Compose. Validate the selected provider rather than assuming equal flag/feature support.

On Windows, select the reviewed provider for the current process:

```powershell
$env:PODMAN_COMPOSE_PROVIDER = 'C:\Tools\compose\docker-compose.exe'
& $env:PODMAN_COMPOSE_PROVIDER version
podman compose version
podman compose --help
```

Adapt the illustrative path to the verified installation. Podman prefers `docker-compose` over
`podman-compose` when both are discovered; explicit selection prevents accidental changes after a
PATH update. `podman compose` arranges provider connectivity to its selected Podman socket.
Verify conflicting Docker environment/context settings rather than assuming they are harmless.

### Coexistence and Removal

Keep Docker and Podman endpoints explicit. Prefer `podman compose` for the Podman path rather than
a global `docker=podman` alias. For Docker API tools, derive the endpoint from the actual machine
and follow the [upstream compatibility guide](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility);
do not hardcode a Linux socket into Windows configuration or expose an unauthenticated TCP API.

Images, volumes and credentials do not automatically move between engines. Rootful and rootless
Podman stores are also separate. Before removing Desktop, independently install every approved
client still needed and plan protected state export/import separately. Never delete Desktop or its
data as a setup side effect.

## Other Approved Alternatives

* Docker Engine in approved Linux/WSL or on an approved remote host can retain Docker CLI/BuildKit
  semantics without Docker Desktop. Verify policy, daemon lifecycle and remote mount semantics.
* [Rancher Desktop](https://docs.rancherdesktop.io/tutorials/working-with-images/) offers Moby with
  Docker CLI or containerd with nerdctl. Select the matching engine; these paths are not identical.
* [WSLC](#wslc-without-docker-desktop) can provide capability-checked Windows-local image validation,
  not an assumed Compose or publication replacement.

Select one justified path. Do not install several engines or Kubernetes merely to compare tools.

## WSLC Without Docker Desktop

WSL Containers runs without a Docker daemon. Verify availability in the installed WSL release;
not every WSL installation includes it. Follow the
[official prerequisites](https://github.com/microsoft/WSL/blob/master/nuget/Microsoft.WSL.Containers/docs/README.MD#prerequisites)
and ask before installing/updating WSL. Do not start Desktop as a fallback.

Discover `wslc`, then inspect its version and installed `build`, `run`, `logs` and `stop` help.
Reuse existing Dockerfiles and ignore files. With approval, build/run the native platform and verify
the expected endpoint or process result, then clean up only the created resources using installed
CLI options. Confirm loopback port mappings and retain non-root execution.

Check advanced COPY flags, cache/secret mounts, platform arguments and stage selection before use.
The [architecture limitations](compatibility.md#capability-matrix) distinguish ARM64 host support
from cross-platform builds. Do not claim Compose, registry/image-store interoperability, Buildx
checks, multi-platform indexes, provenance or SBOM support from a native smoke test.
