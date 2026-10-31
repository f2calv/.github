# Development

How to validate changes to the shared instructions, skills and scripts in this repository. Authoring
rules live in the repository's own [Copilot instructions](../.github/copilot-instructions.md).

## Tests

The central Pester runner discovers root script tests and every skill's `scripts/tests` directory.
With PowerShell 7.4+, Pester 5.7.1, Git, Bash, Helm, Mike Farah yq v4, the .NET 10 SDK and npm
available, run from the repository root after test approval:

```powershell
npm run test:ps
npm run test:release-train
```

`test:ps` runs the complete suite; pass `-- -TestPath <path>` for a focused selection. The
release-train command is a focused alternative, not a suite omitted by `test:ps`. Empty or failed
runs return a nonzero exit code. Some fixtures use `chmod` and shebang fake commands, so run the
suite on Linux or in CI rather than on a Windows host.

After changing any skill, run the [skill library checks](../.github/skills/skill-library/SKILL.md#validate-and-bump)
before committing; CI rejects missing sidecars and unbumped or over-bumped versions.

The separate `dotnet-examples` CI job builds the self-contained parsing solution in Release,
including its benchmark project, and runs at least the 16 expected parsing tests under .NET 10.
It does not execute benchmarks. From the
[fixture directory](../.github/skills/dotnet-performance/examples/utf8-count/), the equivalent local
commands (with build/test approval) are:

```powershell
dotnet build Example.CountParsing.slnx --configuration Release
dotnet test --project src/Example.CountParsing.Tests/Example.CountParsing.Tests.csproj --configuration Release --no-build --filter-trait "Category=Parsing" --minimum-expected-tests 16
```

## Validation Boundaries

| Evidence | Persistent coverage | Still requires separate execution or approval |
| --- | --- | --- |
| Skill discovery, maintenance sections and local links | Central Pester checks | Editor activation and external links |
| Skill versions, packaging and catalog | Pester suite and the CI skill library check | Consumer installation from the published catalog |
| Container and caller templates | Static audit and synthetic argument/exit tests | Image builds, registry publication and deployment |
| Helm/GitOps/ingress examples | Real local Helm render/lint/schema/package checks and structural ownership assertions | Cluster bootstrap, admission, routing, certificates and rollback |
| Forms, policy overrides and cleanup examples | Form comparisons, pure policy composition, mocked APIs and synthetic source edits | Actual GitHub operations and consumer compatibility |
| Appsettings build items | SDK-only synthetic build/publish/package tests extracted from the configuration instructions, including missing local files and older source timestamps | Real application startup and private configuration values are not exercised |
| REST collections and network-change evidence | Static structure, variable and approval-boundary checks | Requests, live network measurements and fault recovery |
| Self-contained parsing fixture | Separate CI job builds all three projects and runs xUnit tests; Dependabot maintains its packages | Benchmark execution remains explicitly requested |
| Other .NET integration examples | Structural Pester checks | Consumer-bound compile/HTTP fixtures and published-package consumption are not continuously executed |

The other .NET compile, loopback HTTP and benchmark checks performed while authoring examples remain
point-in-time evidence. Repeat them after relevant SDK/API changes.

<!-- TODO: Extend dotnet-examples with persistent synthetic integration fixtures:
1. Extract the MCP/controller snippets into isolated hosts, using fake authentication and source
services; assert actual wire shapes and API Explorer without claiming production OAuth coverage.
2. Turn the release-consumer laboratory into an isolated local-feed test with fresh caches and
negative partial-publication checks; never query synthetic IDs on a public registry.
3. Pin published shared-library contracts before adding leadership/exception compilation; do not
require adjacent workstation checkouts or replace real API validation with invented stubs.
These remain deferred because the earlier temporary harnesses were not retained as maintainable
fixtures and some shared APIs are provisional. Prefer an explicit snippet-to-fixture build step
over copied source that drifts. Revisit when the contracts are published and fixtures have their own
cleanup, timeout and failure-path tests. Benchmarks and live infrastructure stay opt-in. -->

<!-- TODO: After an authorized push, verify dotnet-examples reports successfully on the current
PR head and inspect Dependabot's resolver log for the nested NuGet root. Only then add the actual
emitted check context to this repository's required-check policy if it should independently block
merges. Deferred because local validation cannot prove GitHub scheduling or resolver behavior;
the release job already depends on dotnet-examples, without modifying remote rulesets here. -->
