# .NET Artifact Identity

How a .NET image and its entry assembly carry one version and source revision; the audit's DF026
rule and the manual checks in [audit reference](audit-and-scripts.md#audit-rules) enforce it.

- Start .NET service images from the canonical templates bundled with this skill:
  `templates/dotnet-service.dockerfile.tmpl` for published images and
  `templates/dotnet-service-debug.dockerfile.tmpl` for sibling-project Debug images, or
  `templates/dotnet-service-aot.dockerfile.tmpl` for Native AOT. Resolve their
  [shared version inputs](dotnet-version-inputs.md). Preserve their
  argument order, stage order, restore/publish option order and line wrapping. Change only marked
  placeholders and workload-required sections; explain every structural deviation beside it.
- `WORKLOAD` names the produced assembly/native executable without `.dll`; `PROJECT` independently names its
  project file. The publish stage creates `/app/publish/entrypoint.dll` as a symlink to
  `$WORKLOAD.dll` for managed output, whose runtime uses `ENTRYPOINT ["dotnet", "entrypoint.dll"]`.
  Native AOT instead links `$WORKLOAD` to `/app/publish/entrypoint` and executes
  `ENTRYPOINT ["/app/entrypoint"]` on runtime-deps. This keeps each deployment model's
  entrypoint identical on full, chiselled and Debug images without runtime shell expansion.
- Retain the complete OCI label block in Debug images as well as published images. Debug profile
  relaxation permits omission for nonstandard investigation images; it is not the default for .NET
  sibling-project variants, which stay structurally aligned with their published counterpart.
- Every .NET application image accepts `VERSION` and `GIT_COMMIT` build arguments with public-safe
  local defaults. Pass them to `dotnet publish` as `-p:Version="$VERSION"` and
  `-p:SourceRevisionId="$GIT_COMMIT"` so the entry assembly carries the same semantic version and
  source revision as the image.
- The workflow or script invoking the build derives `VERSION` from the repository's versioning
  authority and supplies the same value to the image tag and OCI `version` label. It derives
  `GIT_COMMIT` from the built commit and supplies the same value to `SourceRevisionId` and the OCI
  `revision` label.
- Assembly/native build metadata is the running application's artifact identity; OCI labels are the container's
  artifact identity. Do not redefine either through Helm values, Kubernetes annotations or runtime
  environment variables. Runtime configuration carries deployment context only.
- Keep repository-wide assembly metadata declarations in the root `Directory.Build.props`, not in
  individual project files or Dockerfiles. Generate `GitRepository`, `GitBranch`, `GitCommit`,
  `BuildWorkflow`, `BuildRunId` and `BuildRunNumber` from the corresponding MSBuild properties; the
  Docker template passes those properties to `dotnet publish`.
