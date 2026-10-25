# Project Inventory and Provisional Classification

Run the [inventory script](../scripts/Get-DotNetProjectInventory.ps1) before agreeing naming or
folder migrations. It reads selected Git worktrees; it never builds, restores, invokes MSBuild,
executes imported targets, fetches remotes or changes source files.

## Invocation

From this skill's directory, pass the exact repository set:

```powershell
$report = & ./scripts/Get-DotNetProjectInventory.ps1 -RepositoryPath @(
    'C:\work\example-library',
    'C:\work\example-application',
    'C:\work\example-tooling'
)
$report.Projects | Format-Table Repository, Project, Role, Confidence
$report.Projects | Where-Object { $_.ReviewNotes.Count -gt 0 } |
    Select-Object Repository, Project, ReviewNotes
```

No output file is created automatically. If retaining the report, serialize the entire object with
`ConvertTo-Json -Depth 12` to an approved local path. Report paths, package identities and reference
graphs can reveal private repositories: never commit a workspace report to this public skill.
Do not export arbitrary configuration properties, credentials or source excerpts.

Tracked working-tree files are the default, including modifications not yet committed.
`-IncludeUntracked` adds non-ignored untracked files; it does not include ignored `bin`, `obj`,
local configuration or dependency caches. Deleted tracked projects are recorded separately instead
of silently disappearing. Repositories with zero projects remain represented.

## Evidence and Classification

| Candidate role | Evidence used | Important boundary |
| --- | --- | --- |
| `test-suite` | Direct `IsTestProject=true`, or a test-runner package plus test attributes/test suffix | Takes precedence over `OutputType=Exe`; MTP tests are executable |
| `benchmark` | BenchmarkDotNet package and benchmark code | Not a correctness test suite or production host |
| `integration-test-host` | Executable/Web SDK shape plus TestHost/IntegrationHost naming or supporting README | Verify actual test consumers and isolation before accepting the role |
| `sample-application` | Executable/Web SDK shape under sample/example/fixture paths | A runnable sample is not automatically an integration-test application |
| `cli-tool` | Executable with `PackAsTool=true` | Packability does not establish publication |
| `application` | Direct executable declaration or Web SDK executable default | Production deployment and host purpose still need review |
| `frontend-client` | Blazor WebAssembly SDK | Browser application, not its server host |
| `test-support-library` | Testing/Fixtures suffix plus fake/stub implementation, support documentation or incoming test-suite references | Name plus consumers alone is low confidence; may be published, not a test runner |
| `backend-library-candidate` | Library with controller/background-feature signals in an application dependency closure | Shared infrastructure libraries can also match; confirm application ownership |
| `class-library` | No stronger direct role evidence | Includes contracts, clients, DI composition, generators and unresolved shapes |

The report includes SDK, project/folder names, source count, signal labels, nearest shared build
files, allowlisted property declarations, package references, project references, incoming edges
and solution membership. Declaration values are **not effective MSBuild properties**:

* Conditions, property functions, imported SDK defaults, `Choose`, target execution and custom
  build logic are not evaluated. Conditional/shared role declarations lower confidence.
* The nearest tracked `Directory.Build.props` and `.targets` are read. Literal in-repository
  imports are inspected recursively, including `MSBuildThisFileDirectory`; dynamic, external or
  missing imports are not followed. All import conditions remain unresolved.
* Reference edges describe possible declared dependencies across configurations, not one resolved
  Debug/Release graph. External references are recorded but their repositories are not discovered.
* Source signals use heuristics, not Roslyn. Comments, string literals, conditional compilation,
  source generators and linked/removed Compile items can affect precision. No source excerpt is
  emitted. Nested project directories are excluded from a parent project's source signals.
* File/SDK names suggest a role; they cannot prove business architecture. Even high-confidence
  rows retain `ReviewRequired=true` because naming changes need explicit approval.

Malformed XML, prohibited DTDs, path escapes and unreadable files fail the inventory instead of
turning failures into library classifications. No partial report is emitted as a successful result.

## Review Procedure

1. Confirm each candidate against the project README, entry point, public API and actual consumers.
2. Separate test suites, reusable testing libraries, sample apps and test-only host processes.
   Do not rename all `.Testing` projects to `.Tests`.
3. Compare backend candidates by responsibility, not suffix. A library that owns one application's
   controllers/background/domain processing may differ from a published integration library or
   shared host bootstrap even when all contain services.
4. Inspect framework/configuration-specific evaluated items separately when the static report flags
   uncertainty. Obtain approval before executing build tooling; MSBuild evaluation is not inert XML
   parsing and may execute property functions or custom imports.
5. Agree a role-to-name table and per-project mapping before moving anything. Possible review
   vocabulary includes `.Tests`, `.Testing`, `.TestHost`, `.Sample`, `.Benchmarks`, `.Backend`
   and `.App.Server`; this is **not an enforced rename policy**.
6. Keep project/folder names separate from `AssemblyName`, `RootNamespace`, `PackageId`,
   executable names and published contracts. A folder rename need not change every identity.
7. For an approved migration, preserve Git history with moves; update solution entries, project
   references, conditional sibling substitutions, Docker manifest copies, CI paths, friend
   assemblies, reflection, packaging and documentation. Validate the complete affected graph.

The smallest useful outcome of this phase is an inventory plus reviewed role decisions and a
proposed rename map. Do not create a new shared abstraction, split projects or rename namespaces
solely to satisfy an attractive naming scheme.
