---
name: editorconfig-management
description: 'Audit, generate, align, tighten, and validate .editorconfig files across one repository or a multi-root workspace. Use when adding EditorConfig, synchronizing shared formatting policy, checking drift, selecting language profiles, enforcing .NET analyzers, fixing formatting fallout, or planning a staged cross-repository rollout.'
argument-hint: '[repositories=current-workspace|path,...] [mode={audit|generate|check|tighten}] [profile={Base|DotNet|Go|Python|Rust|Terraform}]'
user-invocable: true
compatibility: 'Generation requires PowerShell 7.4. .NET tightening requires a compatible .NET SDK and repository build entry point.'
---

# EditorConfig Management

Manage tracked root `.editorconfig` files from the central composable fragments. Keep the universal
text policy consistent, preserve formatter ownership, and tighten analyzer policy in measured
tranches whose complete fallout can be fixed and validated together.

## Scope And Safety

- Limit fleet operations to explicit repository paths or the active workspace folders. Never infer
  scope by enumerating a parent clone directory.
- Treat every Git repository independently. Inspect its instructions, active branch, working tree,
  build entry point, language manifests, and existing `.editorconfig` before editing.
- Never overwrite or stage unrelated changes. Preserve existing user edits and generate into the
  current working tree only after identifying the intended profile and exceptions.
- Audit before editing. Report missing files, profile drift, deliberate overrides, text-hygiene
  violations, build-policy gaps, and expected cleanup surface.
- Generated `.editorconfig` files remain tracked in each repository. EditorConfig has no import
  mechanism, so consumers must not depend on the central checkout at editor startup.
- Do not install hooks or format an entire repository speculatively. Apply mechanical cleanup only
  after measuring violations and keep it separate from behavioral changes.
- Obtain any approval required by the workspace rules before running builds or tests.

## Central Sources

The central repository owns:

| Path | Purpose |
| --- | --- |
| `.config/editorconfig/base.editorconfig` | Universal encoding, LF, indentation, and whitespace policy |
| `.config/editorconfig/dotnet.editorconfig` | .NET and C# conventions plus staged analyzer severity |
| `.config/editorconfig/go.editorconfig` | Go and `gofmt`-compatible indentation |
| `.config/editorconfig/python.editorconfig` | Python and TOML editor settings |
| `.config/editorconfig/rust.editorconfig` | Rust and `rustfmt`-compatible settings |
| `.config/editorconfig/terraform.editorconfig` | Terraform and HCL indentation |
| `.scripts/Set-EditorConfig.ps1` | Idempotent generator and read-only drift checker |
| `.scripts/tests/Set-EditorConfig.Tests.ps1` | Generator regression coverage |
| `docs/editorconfig.md` | Source model, enforcement strategy, rollout, and rollback rationale |

Change policy in the fragments, not in generated consumer files. Regenerate every affected
repository after a fragment change.

## Profile Selection

Every profile includes `Base`; select one additional profile from owned tracked source:

| Evidence | Profile |
| --- | --- |
| C# source, project files, or a .NET solution | `DotNet` |
| Go module or Go source | `Go` |
| Python project or Python source | `Python` |
| Cargo workspace or Rust source | `Rust` |
| Terraform/OpenTofu roots or HCL | `Terraform` |
| Workflows, actions, Helm, Markdown, JSON, YAML, or mixed text without a supported language profile | `Base` |

For a repository spanning multiple profiled languages, choose the primary profile and append a
small repository-owned override fragment for the additional language sections. Do not copy an
entire central profile into an override.

## Required Workflow

### 1. Establish The Repository Set

1. Resolve roots from explicit inputs or active workspace folders.
2. Confirm each root with Git metadata and record its current branch and working-tree state.
3. Read repository-specific instructions that apply to `.editorconfig`, build files, source cleanup,
   workflows, documentation, commits, and publication.
4. Record repository visibility before any commit, push, issue, or pull-request operation.

### 2. Audit Existing Policy

For each repository:

1. Detect the language profile from tracked manifests and source files.
2. Inspect the root `.editorconfig`, if present, and compare effective sections with the generated
   profile.
3. Inspect formatter configuration, `.gitattributes`, pre-commit hooks, and build properties for
   conflicting ownership.
4. For .NET, inspect `TreatWarningsAsErrors`, `EnforceCodeStyleInBuild`, analyzer severities,
   `NoWarn`, and `WarningsNotAsErrors`. A suppression that defeats central policy is drift.
5. Measure missing final newlines, trailing whitespace outside Markdown, and JSON/YAML indentation.
   Do not rewrite files during the audit.
6. Classify differences as `Missing`, `Generated drift`, `Policy drift`, `Hygiene violation`, or
   `Intentional override` with its documented rationale.

### 3. Generate Or Check

From the central repository root, generate a tracked file:

```powershell
./.scripts/Set-EditorConfig.ps1 -RepositoryPath <repository-path> -Profile <profile>
```

Perform a read-only drift check:

```powershell
./.scripts/Set-EditorConfig.ps1 -RepositoryPath <repository-path> -Profile <profile> -Check
```

Preview a write with `-WhatIf`. Pass one or more `-OverridePath` values only for documented,
durable repository exceptions. After generation, immediately run `-Check`; a generated file that
does not pass its own drift check is a failure.

### 4. Apply Mechanical Cleanup

1. Add one LF byte only to tracked text files missing a final newline.
2. Use a structured formatter for JSON, JSONC, or JSON5; never reserialize comment-bearing files
   through a strict JSON parser.
3. Preserve Markdown trailing spaces because two spaces encode a hard line break.
4. Use the language's native formatter where it owns syntax: `dotnet format`, `gofmt`, `rustfmt`,
   Terraform formatting, or the repository's pinned Python formatter.
5. Scope formatting to measured violations. Review large generated or dashboard diffs separately.
6. Run `git diff --check` and parse every changed structured file.

### 5. Tighten .NET Enforcement

The current build-breaking tranche is:

- `IDE0051`: unused private members
- `IDE0052`: unread private fields
- `IDE0055`: formatting
- shared interface, type, and non-field-member naming rules

Require both build properties in the root `Directory.Build.props`:

```xml
<TreatWarningsAsErrors>true</TreatWarningsAsErrors>
<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
```

Remove contradictory `NoWarn` or `WarningsNotAsErrors` entries. Fix dead code, formatting, and
naming at the source; do not weaken severity to make a build pass. A documented wire-contract
naming exception may remain narrowly suppressed when renaming would break the external schema.

Keep other shared style preferences standardized as suggestions until their fleet fallout has been
measured. Promote only a small related tranche at a time. Namespace, public API, and architecture
changes require their own reviewable tranche rather than being hidden inside formatting cleanup.

### 6. Validate

For every affected repository:

1. Run the generator with `-Check`.
2. Confirm UTF-8 without BOM, LF endings, one final newline, and no forbidden trailing whitespace.
3. Parse changed JSON, YAML, XML, TOML, and project files with repository-approved tooling.
4. Run the repository's authoritative lint or pre-commit command; `git diff --check` alone does not
   prove hooks such as `end-of-file-fixer` are satisfied.
5. For .NET, build the complete solution across every target framework. Where Debug and Release
   solutions use different project/package graphs, validate both. Fix every warning promoted to an
   error. A missing platform workload is an environment blocker, not evidence that policy passes.
6. Run `git diff --check`.
7. Run the focused generator Pester suite after generator or fragment changes.
8. Re-run the inventory and prove every repository is either drift-free or has a documented
   override.

### 7. Commit And Publish

1. Keep central fragment/generator changes separate from generated consumer rollouts.
2. Keep mechanical text cleanup separate from behavioral changes when either diff is large.
3. Before committing to a public repository, run the central privacy skill and scanner.
4. Follow repository branch conventions and local safe-hour rules. Never commit directly to a
   default branch unless a repository-specific exception explicitly permits it.
5. Push and create pull requests only with explicit authorization. Public pull-request text must not
   identify private repositories or private implementation details.
6. Verify each pull request's base, head, labels, assignee, checks, and complete branch diff.

## Reporting

Report:

- repositories and profiles audited, generated, or checked;
- policy and hygiene drift found and corrected;
- deliberate overrides retained and why;
- .NET diagnostics promoted and source fixes required;
- validation performed, build blockers, and checks not run;
- branch, commit, push, and pull-request state when publication is requested.

Keep public reports free of private repository names, coordinates, paths, topology, and operational
details.
