# .NET Service Template Inputs

Use these templates for a framework-dependent .NET service with central build/package properties.
They are authoring inputs, not Dockerfiles ready to build before substitution. No renderer is
required: replace the literal tokens and retain the remaining ordering.

## Select the Pair

| Build | Dockerfile input | Ignore input | Destination at repository root |
| --- | --- | --- | --- |
| Published | [Service](../templates/dotnet-service.dockerfile.tmpl) | [Service ignore](../templates/dotnet-service.dockerignore.tmpl) | `Dockerfile`, `.dockerignore` |
| Sibling-source Debug | [Debug service](../templates/dotnet-service-debug.dockerfile.tmpl) | [Debug ignore](../templates/dotnet-service-debug.dockerignore.tmpl) | `Dockerfile.Debug`, `Dockerfile.Debug.dockerignore` |

Dockerfile-specific ignore files replace, rather than extend, the root ignore file. Keep the
build-output and secret exclusions in both. These examples keep test sources in the context for
an optional isolated test target; the publish-stage `COPY --exclude` keeps them out of that layer.

## Resolve Inputs

| Token | Synthetic value | Meaning |
| --- | --- | --- |
| `{{WORKLOAD}}` | `Example.Service` | Output `AssemblyName`, without `.dll`; not necessarily the project filename |
| `{{PROJECT}}` | `src/Example.Host/Example.Host.csproj` | Repository-relative project path, using Docker's `/` separators |
| `{{SOURCE_MANIFESTS}}` | `src/**/*.csproj` | Space-separated existing manifest patterns; include imported props/targets and lockfiles when present |
| `{{IMAGE_DESCRIPTION}}` | `Example background service` | Public-safe plain text; escape Dockerfile-sensitive characters if needed |
| `{{IMAGE_SOURCE}}` | `https://example.com/source` | Replace with the verified public source URL, never private coordinates |
| `{{SPDX_LICENSE}}` | `MIT` | Replace with the repository's actual SPDX license expression |
| `{{DEPENDENCY_COPIES}}` | `COPY deps/Example.Shared /Example.Shared` | Debug-only full source copy matching the consumer's relative project reference |
| `{{DEPENDENCY_DIRECTORY}}` | `Example.Shared` | Debug-only mirrored sibling directory; add an explicit allow-list entry for each additional sibling |

In this example the consumer is rooted at `/repo` inside the build. A reference from
`/repo/src/Example.Host/Example.Host.csproj` to
`../../../Example.Shared/src/Example.Shared/Example.Shared.csproj` resolves beneath
`/Example.Shared`. The Debug manifest copy strips `deps/`, and the full source copy must land at
the same location. Do not replace this with a guessed `/repo/deps` destination.

The existing container build script discovers `COPY deps/<name>` inputs and mirrors sibling
checkouts into the caller's `deps/` directory. Do not place hand-maintained files there; the
workflow owns that generated directory.

## Adapt Only the Required Surfaces

* Add imported root files such as `Directory.Build.targets`, `NuGet.config` or lockfiles to both
  the manifest-copy layer and the matching ignore allow-list when the project actually uses them.
  Never copy a credential-bearing NuGet configuration; use a build secret instead.
* The broad source allow-list is a starting point, not a secret scanner. Inspect everything it
  admits, narrow it to owned build inputs, and exclude additional local-only configuration patterns.
* Choose a runtime supporting the project's framework references and native dependencies.
  Add `EXPOSE` for actual HTTP/gRPC listeners; do not invent ports for a background worker.
* Both templates create `entrypoint.dll` and execute `dotnet entrypoint.dll`. Do not mix in an
  apphost entrypoint or a runtime shell to expand the assembly name.

## Validate

From the central skill directory, run `./scripts/Test-Dockerfile.ps1 -Path <absolute-caller-path>`
after substitution. Require no unresolved `{{...}}` tokens and no blocking audit findings.
Check that every `COPY` input survives the selected ignore file.

With build approval, run BuildKit checks and a native-platform build from the caller's root,
using `-f Dockerfile` or `-f Dockerfile.Debug` explicitly. Confirm the actual assembly exists,
the entrypoint starts it, and shutdown is clean. The static audit is not proof of a successful
restore, publish, context transfer or runtime start.
