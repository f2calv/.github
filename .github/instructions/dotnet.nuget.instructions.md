---
description: '.NET NuGet package authoring, central version management, local project substitution, publication and dependent release conventions.'
applyTo: '**/*.csproj,**/*.fsproj,**/*.vbproj,**/Directory.Build.props,**/Directory.Packages.props,**/NuGet.config,**/*.nuspec,**/packages.lock.json'
---

# .NET NuGet

## Package Metadata

- Keep repository-wide NuGet metadata in the root `Directory.Build.props`, including authors,
  project URL, licence file, readme file, repository metadata, symbol packaging and deterministic
  continuous-integration settings.
- Make packaging opt-in. Set `IsPackable=false` centrally and enable it only on projects that publish
  a package or .NET tool.
- Keep package IDs stable. Set `PackageId` only when it intentionally differs from the project name.
- Include the package README, licence and symbols through shared build properties rather than
  repeating metadata in every project.

## Central Package Management

- Define every NuGet package version in the root `Directory.Packages.props` and keep
  `ManagePackageVersionsCentrally` enabled.
- Reference packages with versionless `<PackageReference Include="..." />` items in project files;
  the version resolves centrally.
- Add a new package version to `Directory.Packages.props` in the same change that first references it.
- Use exact versions for internally released packages. Do not use floating versions or ranges in a
  release train.
- When one repository publishes several packages under one repository version, keep a consumer's
  references to that package set aligned unless the producer documents an exception.

## Project and Package References

- Reference projects inside the same repository with `ProjectReference`; reference published
  projects outside it with `PackageReference`.
- Where a repository consumes libraries it also develops locally, use conditional references:
  `ProjectReference` in Debug for local iteration and `PackageReference` in Release for the published
  version.
- Keep Debug and Release references semantically equivalent. A project substituted locally in Debug
  must resolve to the corresponding package in Release.
- Build the Debug solution to validate source-level integration. Build the Release solution after an
  upstream publication to prove the exact package version restores and compiles.

## Dependency Updates

- Update package versions through the structured MSBuild XML, not broad text replacement.
- Assess every active centrally managed package during a full dependency update, including
  development and test dependencies. Ignore commented-out package declarations.
- Prefer the newest stable compatible version. Do not adopt a prerelease unless the repository
  already uses that prerelease line or the user explicitly approves it.
- Update every consumed package from the same producer to the verified release version in one change.
- Commit generated lock-file changes when the repository uses locked restore. Never hand-edit a lock
  file.
- Review the complete pull request diff before classifying a dependency update. Source, test,
  workflow, build or documentation changes make it a mixed change even when package versions also
  changed.
- Treat security advisories as release inputs. Record unresolved transitive advisories through the
  warning policy described in the general .NET instructions rather than suppressing them.

## Package Holds

- Document a deliberate exact hold or major-version ceiling in the consuming repository's
  `.github/copilot-instructions.md`. Name the package or family, exact version or permitted major
  line, compatibility reason, and condition that permits reassessment.
- Preserve an exact hold during automated dependency updates. A major-version ceiling may advance to
  the newest stable compatible version within that major line. Report the newest observed version
  and constraint reason rather than silently skipping the package.
- Keep target-framework-specific versions as separate conditioned `PackageVersion` items. Never
  remove or broaden a condition merely to align version numbers.
- Reassess holds during each full dependency update, but change one only through a dedicated,
  explicitly approved compatibility migration with the affected target frameworks validated.
- An undocumented incompatibility blocks the release train until its cause is understood and either
  fixed or recorded as a repository-specific hold.

## Publication

- Publish packages only through the repository's established CI workflow and trusted package-source
  authentication. Never put a NuGet API key in source, configuration, logs or checkpoint state.
- Derive the package version from the immutable release tag produced by CI. Do not predict a release
  version locally and use it as publication evidence.
- A successful push is not proof that consumers can restore a package. Verify every expected package
  ID and exact version through the configured package source's restore endpoint before updating
  downstream repositories. Version 1 of the `dotnet-release-train` skill supports public nuget.org
  only; authenticated feeds require a separate credential-safe implementation.
- Do not continue a dependent release train when one package from a multi-package producer is absent.
- Use `--skip-duplicate` only to make an idempotent retry safe. It does not permit rebuilding or
  replacing an immutable published version.

## Release Trains

- Use the `dotnet-release-train` skill for dependency-ordered releases across repositories.
- Persist repository coordinates, dependency topology and private project details only in the local
  release-train checkpoint. Do not add them to reusable public instructions or examples.
- Pause downstream work until the upstream GitHub release and every consumed NuGet package version
  are verified.
- Rebuild each consumer in Release after changing internal package versions, even when its Debug build
  already succeeds against local project references.
