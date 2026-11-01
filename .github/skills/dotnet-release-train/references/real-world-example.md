# Real-World Example

One concrete train across public repositories, ordered by dependency wave.

## Real-World Example: f2calv .NET Release Train

The public f2calv repositories release in this order. Indented repositories within a wave do not
depend on one another.

- **Tooling wave**
  - Actions: `gha-release-versioning` and `gha-dotnet-nuget` (the NuGet publish action) before the
    `gha-workflows` reusable workflows that consume them.
  - Charts: `helm-charts`, whose `workload` chart is bundled by every application chart.
  - `.github`, merged last of the whole train.
- **Base library**: `CasCap.Common` and its `CasCap.Common.*` packages.
- **Direct consumers**, each updating every consumed `CasCap.Common.*` package together:
  - `CasCap.Api.Azure`, releasing all `CasCap.Api.Azure.*` packages.
  - `CasCap.Api.SignalCli`.
  - `CasCap.Api.GooglePhotos`.
  - `yamlizr`, released through its global-tool workflow.
- **Second-level libraries**:
  - `CasCap.Api.Voice`, after `CasCap.Api.Azure`.
  - `CasCap.GooglePhotosCli`, after `CasCap.Api.GooglePhotos`, through its global-tool workflow.
- **Platform packages**:
  - `agentizr` releases the Agent Runtime contracts and client; its host ships as an image and chart.
  - `signalizr` releases its client, Comms and Comms AI packages together, after the Agent Runtime
    packages are on NuGet.
- **Applications**: `SmartHaus` and `tutorizr`, plus private application consumers in the workspace.
