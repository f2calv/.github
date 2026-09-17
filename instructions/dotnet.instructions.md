---
description: '.NET solution and build structure — Directory.Build.props, central package management, solution format, SDK selection, target frameworks and analyzers.'
applyTo: '**/*.csproj,**/*.slnx,**/*.sln,**/Directory.Build.props,**/Directory.Build.targets,**/Directory.Packages.props,**/global.json'
---

# .NET

## Central Build Configuration

- Keep shared MSBuild properties in the root `Directory.Build.props` — root namespace, language version, `ImplicitUsings`, `Nullable`, `GenerateDocumentationFile`, warning policy, NuGet package metadata (authors, project URL, licence file, readme file, symbol packaging) and `ContinuousIntegrationBuild` for deterministic CI builds.
- Keep individual project files minimal — only project-specific properties and references belong there.
- Centralise warning suppressions (`NoWarn`) in `Directory.Build.props`, with a comment naming each suppressed diagnostic and why it is suppressed. Never suppress a diagnostic inline in a project file without a comment.
- Use conditional property groups for cross-cutting project categories rather than repeating settings per project — for example disabling `GenerateDocumentationFile` for test projects, and gating `IsPackable` so packaging is opt-in.

## Language and Compiler Settings

- Enable nullable reference types and implicit usings repository-wide; do not disable either per project without a recorded reason.
- Treat warnings as errors. Where a specific diagnostic must be allowed through, list it in `WarningsNotAsErrors` (so it still surfaces) rather than in `NoWarn`.
- A security advisory raised by a transitive dependency that has no direct reference to remove and no fixed upstream release belongs in `WarningsNotAsErrors`, never in `NoWarn` — suppressing it hides a real vulnerability. Record the advisory identifier and why it cannot yet be resolved, and re-check on every dependency bump.

## Analyzers

- Configure analyzer severities in `.editorconfig`, which is the single source of truth for style and analyzer rules; enable `EnforceCodeStyleInBuild` so style rules are enforced by the compiler and not only by the IDE.
- Treat unused-member and unread-field diagnostics as actionable dead code and remove the flagged members.
- Analyzer packages are declared once centrally and flow to every project; do not add them ad hoc per project.

## Central Package Management

- Define every NuGet package version in the root `Directory.Packages.props` and keep `ManagePackageVersionsCentrally` enabled.
- Reference packages with versionless `<PackageReference Include="..." />` items in project files; the version resolves centrally.
- Add a new package version to `Directory.Packages.props` in the same change that first references it.

## Project and Package References

- Reference a project inside the same repository with `ProjectReference`; reference anything published outside it with `PackageReference`.
- Where a repository consumes libraries it also develops locally, use a conditional reference — `ProjectReference` in Debug for local iteration, `PackageReference` in Release for the published version — so Release always builds against the shipped package.

## Solution Format

- Use the modern XML `.slnx` solution format. Convert legacy `.sln` files rather than maintaining the old format alongside.
- Where Debug and Release variants exist, name them `<Name>.Debug.slnx` and `<Name>.Release.slnx`, matching the repository name.
- The Debug solution wires local `ProjectReference` items to sibling libraries; the Release solution uses published `PackageReference` items.
- Prefer the Debug solution for local builds; CI builds the Release solution.

## Target Frameworks

- Libraries intended for wide consumption multi-target the supported .NET releases; applications target a single framework.
- A change that compiles on one target framework must be verified on every target framework before it is considered done.

## SDK Selection

- Stable .NET releases do not require an SDK version in `global.json`; let the installed compatible stable SDK and the CI setup step select it.
- Pin the SDK `version` and `rollForward` policy when using a preview SDK, isolating an SDK regression, or when a workflow requires bit-for-bit reproducibility.
- Keep `global.json` when it configures repository-wide .NET CLI behaviour without pinning an SDK, such as selecting the test runner.

## Verification

- After any refactoring, build the **entire solution** rather than only the affected project, so compilation errors in dependent projects surface immediately.
- Where Debug and Release solutions both exist, build the Debug solution locally; it is the one wired to local project references.
- Ask before running a build. Never run tests automatically — they may be integration tests requiring credentials or external services.
