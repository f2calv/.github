# EditorConfig Generation

The central repository owns composable EditorConfig fragments and the generator used to produce
tracked root `.editorconfig` files. This keeps editor behavior deterministic without relying on
unsupported EditorConfig imports or copying an opaque monolithic file by hand.

## Source Model

The source fragments live under `.config/editorconfig/`:

| Fragment | Purpose |
| --- | --- |
| `base.editorconfig` | Universal encoding, line-ending, whitespace, and indentation policy |
| `dotnet.editorconfig` | Strict .NET and C# formatting, naming, dead-code, and style policy |
| `go.editorconfig` | Go indentation consistent with `gofmt` |
| `python.editorconfig` | Python line length and TOML indentation |
| `rust.editorconfig` | Rust line length and TOML indentation consistent with `rustfmt` |
| `terraform.editorconfig` | Terraform and HCL indentation consistent with the native formatter |

Every generated file starts with the base fragment. A language profile appends its corresponding
fragment. A repository with a documented exception may pass one or more override fragments, which
are appended in order. Overrides must contain only the smallest deliberate difference from the
central policy.

Generated `.editorconfig` files remain tracked in each repository. Reviewers can therefore inspect
policy changes normally, and a repository remains clone-and-run friendly without requiring the
central repository at editor startup.

## Generate And Check

Generate a baseline-only file:

```powershell
./.scripts/Set-EditorConfig.ps1 -RepositoryPath ../example-repository -Profile Base
```

Generate the strict .NET profile:

```powershell
./.scripts/Set-EditorConfig.ps1 -RepositoryPath ../example-dotnet-repository -Profile DotNet
```

Perform a read-only drift check by adding `-Check`. The command exits nonzero when the tracked file
does not match generated output. Use `-WhatIf` to preview a write operation without changing a file.

## Enforcement

The first enforcement tranche promotes formatting (`IDE0055`), unused private members (`IDE0051`
and `IDE0052`), and naming rules to warning. .NET repositories set `EnforceCodeStyleInBuild` and
`TreatWarningsAsErrors`, so these violations fail builds rather than remaining editor suggestions.
Other style preferences remain standardized suggestions until a measured rollout can promote a
small related set without mixing mechanical cleanup with namespace, API, or architecture changes.

Formatting settings remain in EditorConfig, while `.gitattributes` owns Git checkout line-ending
normalization. Language formatters may apply the declared rules but must not define a conflicting
policy.

## Rollout

Apply policy changes in reviewable stages:

1. Generate the target `.editorconfig` and inspect the policy-only diff.
2. Apply mechanical formatting separately from behavioral changes.
3. Enable `EnforceCodeStyleInBuild` in the repository root `Directory.Build.props`.
4. Build the complete solution and correct every warning promoted to an error.
5. Run the generator with `-Check` and the repository's normal validation before publishing.

Do not weaken or suppress a promoted rule merely to make a rollout pass. Promote later style rules
in small measured tranches, fix their complete fleet fallout, and add an override only when a
repository has a documented, durable reason to differ from the shared convention.

## Rollback

Revert the generated `.editorconfig`, the matching `Directory.Build.props` enforcement change, and
the mechanical cleanup together. The previous tracked files restore the prior editor and build
behavior without requiring changes to developer machines.
