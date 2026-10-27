---
name: dotnet-upgrade
description: 'Assess and upgrade .NET major versions, starting with .NET 10 to 11 and evolving for .NET 12 onward. Use for SDK, target-framework and NuGet bumps, release-note analysis, breaking changes, deprecated APIs, and codebase-specific C# convention, runtime and performance opportunities beyond version replacement.'
argument-hint: '[target major] [audit|upgrade]'
user-invocable: true
---

# .NET Upgrade

Upgrade the platform and identify worthwhile improvements it unlocks. A successful upgrade is not
just a passing build or a list of package bumps: it includes an evidence-backed assessment of new
features, obsolete APIs and behavior changes in the actual codebase.

## Scope and Authorities

- `audit` is read-only: report the proposed migration, opportunities and blockers.
- `upgrade` implements platform/package changes and required compatibility fixes. Ask before
  implementing optional modernizations; an audit or upgrade request does not approve them all.
- Use explicit repositories or the current repository, not every sibling checkout. Confirm an
  ambiguous target or fleet scope. With no target specified, propose the latest GA release.
- Read the repository notes and shared .NET, C#, NuGet, configuration and testing instructions
  applicable to the files in scope. Preserve package holds, supported consumers and unrelated edits.
- Use `dotnet-release-train` for producer ordering, publication and consumer propagation;
  `containers-images`, `containers-devcontainer` and `containers-workflows` for their respective surfaces;
  `dotnet-test-platform` for runner changes; `blazor-frontend` and `dotnet-webapi` for frontend/API
  migrations; `dotnet-efcore` for provider/model/query and schema migrations; and
  `dotnet-performance` for measured hot-path changes. Reuse these authorities
  rather than reimplementing their procedures here.
- Ask before builds and tests, stating the intended scope and external prerequisites. Do not
  install SDKs/workloads, deploy, publish, commit or push without the applicable authorization.

## Release References

Load only the references for the releases being crossed. They are research entry points, not a
frozen feature catalogue or permission to enable experimental features.

| Target | Highlights and official sources | Reference status |
| --- | --- | --- |
| .NET 11 from .NET 10 | [Runtime, C# 15, libraries, web, EF and migration watchlist](./references/net11.md) | RC2 evidence checked 2026-10-24; recheck at GA |

For a skipped major, review every intervening release's breaking changes and deprecations. If a
target has no reference yet, research it using the procedure below, then add a concise version
reference in this central skill during an authorized upgrade, not a speculative feature list.

## Workflow

The [worked assessment](./examples/release-assessment.md) shows a mixed-target application,
required bumps, source-backed opportunity ranking, user choices and an honest validation report.
It is synthetic guidance, not an executed upgrade or a fixed package-version recipe.

### Customization Review Is Part of Every Upgrade

Review the applicable .NET-related Copilot instructions **and skills**, including central sources
and repository-specific overrides, alongside the application. Do not wait until a compiler error
or a user request exposes stale guidance.

1. Inventory the authorities actually loaded/referenced: SDK/build, C#, NuGet, analyzers,
   configuration, tests/runner, EF/provider, Web API/Blazor, MCP, performance, containers and release
   workflows where relevant. Include their examples/templates/scripts when the change affects them.
2. Search those authorities for source-version assumptions: fixed language/runtime versions,
   deprecated API advice, retired workarounds, preview flags, package holds, runner/CLI syntax,
   image defaults and newly available conventions. Verify each candidate against official
   target-release guidance and actual consumers rather than replacing version strings wholesale.
3. Add affected customization paths and proposed edits to the decision brief. Classify corrections
   to obsolete guidance separately from optional new conventions; identify retained TFMs and
   consumers that would make a blanket central change unsafe.
4. In an audit, report without editing. During an approved upgrade, update the owning central
   file or genuinely repository-specific override at the justified scope; obtain approval for
   material new conventions just as for optional source modernization. Inspect existing user
   changes first. Never copy central rules into each consumer to make the upgrade self-contained.
5. Validate edited customization frontmatter, local links and affected examples through existing
   repository checks with execution approval. Include updated, deferred and unchanged authorities
   with reasons in the completion report; do not mark the review complete just because application
   builds pass.

Use `agent-customization` for customization authoring. Keep one authority per rule and fold accepted
lessons back into that authority, not only into this skill's version-reference file.

### 1. Establish the Baseline

1. Inspect the worktree and inventory solutions, projects, imported build props/targets,
   `TargetFramework`/`TargetFrameworks`, SDK selection, explicit language/analyzer settings,
   workloads, local tools, central packages, lock files and package sources. Exclude generated
   output and vendored dependencies.
2. Trace CI/reusable workflow inputs, setup steps, build/test scripts, SDK and runtime container
   stages, Compose, Dev Containers, deployment runtime requirements, examples and documentation.
   Identify the owning setting rather than replacing every occurrence of the old version.
3. Determine applications versus published libraries, all retained TFMs, RIDs, OS/CPU targets,
   framework-dependent versus self-contained deployment, AOT/trimming and actual EF providers.
   Identify Debug local-project substitution versus Release published-package dependencies.
4. Record current diagnostics and behavior evidence from existing artifacts; request a baseline
   build/test or benchmark when needed. Do not invent a clean baseline if execution is declined.
   Keep operational identifiers and code out of public web searches.

### 2. Research the Target, Not Just Its Version Number

1. Recheck Microsoft's [support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)
   and [official release records](https://github.com/dotnet/core/tree/main/release-notes).
   State the verification date, GA/RC/preview status, support lifetime, available SDK/runtime patch
   and supported platforms. Do not assume an SDK feature-band version equals a runtime version.
2. If the requested target is prerelease, explain that and ask whether to prepare a read-only
   readiness assessment, use the latest GA, or explicitly adopt the prerelease. A go-live licence
   is not GA. Check feature-level preview/experimental status separately from the release status.
3. Read official release notes for runtime/JIT/GC, libraries, SDK/tooling, C# and the workloads
   actually used: ASP.NET Core/Blazor, EF Core, desktop or mobile. Follow promising sections to
   API documentation, migration guidance and official performance analysis.
4. Separately read breaking-change indexes, obsoletion diagnostics and removals for every crossed
   release, including compiler, SDK, container/OS and database-provider changes. Compilation
   cannot detect all wire-format, authentication, numerical or runtime behavior changes.
5. Verify package compatibility from the actual feeds and publisher/provider guidance. Microsoft,
   EF providers, Aspire, test tools and third-party packages have independent release schedules;
   never force every package to the target .NET major or invent a future version.
6. Use the bundled highlights to start the search, not to stop it. Verify official destinations
   and relevant anchors; discover changed URLs from authoritative indexes rather than guessing
   version-shaped paths. If a source is unavailable, record the gap and do not assert readiness
   for the affected area.

### 3. Present a Codebase-Specific Decision Brief

Before editing, separate:

- **Required migration:** platform/package bumps, compatibility fixes, deployment prerequisites.
- **Automatic gains:** runtime/JIT/library improvements obtained by upgrading and recompiling;
  do not prescribe source rewrites for benefits that need none.
- **Optional improvements:** new APIs, C# idioms, removed workarounds, configuration or tooling
  simplifications justified by real code.
- **Deprecations and breaks:** affected usages, replacements and behavior changes, even when the
  old code still compiles.

Trace candidates to concrete files/symbols and callers. Check existing shared helpers before
proposing new logic. Rank the strongest applicable opportunities by likely impact, effort and risk;
do not pad the report with irrelevant release highlights. Use this shape:

| Class | Evidence in this codebase | Proposed change or replacement | Expected benefit | Risk, prerequisites and validation | Official source |
| --- | --- | --- | --- | --- | --- |

Distinguish measured results from hypotheses and upstream benchmarks; do not transplant a
publisher's percentage into a claim about this application. For each relevant deprecation, name
the API/package/diagnostic, whether it is obsolete or removed, and its documented replacement.
Report reviewed areas with no matches and unverified areas explicitly.

Use a user decision tool to offer the standard upgrade only, the upgrade plus recommended
low-risk improvements, or selection of individual opportunities. Clarify the selected items
before implementation; public API, serialization, schema, authentication and broad convention
changes need explicit scope. New syntax alone is not a reason for a repository-wide rewrite.

### 4. Apply the Approved Upgrade

1. Update the owning TFM declarations and SDK selectors, preserving required multi-targeting,
   conditions and platform suffixes. Raising an application's TFM does not authorize dropping
   supported library consumers. Follow central SDK policy rather than adding a stable SDK pin
   automatically; preserve test-runner and other unrelated `global.json` settings.
2. Update compatible NuGet families, analyzers, source generators, test SDK/runner, provider
   packages and tool manifests through their structured configuration. Respect holds and
   supported TFM combinations. Remove a redundant package only after verifying the target's
   framework reference supplies it. Regenerate existing lock files with restore.
3. Align CI SDKs, scripts, runtime requirements, container build/runtime images and Dev Containers.
   Verify published tags/digests and platform/OS/CPU support; preserve image profiles rather than
   changing distro or adopting AOT incidentally. Never assume a runtime or hosting environment
   supports a new major just because an SDK builds it.
4. Implement required compatibility fixes and approved improvements in coherent batches.
   Preserve cancellation, exception semantics, disposal, ordering, culture, nullability and
   allocations where relevant. Keep public and wire contracts stable unless a change was agreed.
   Do not silence new warnings or re-enable retired behavior to make validation look successful.
5. Update directly affected documentation and examples. For reusable convention improvements,
   propose or apply the appropriate central instruction update only at its justified scope;
   retain application policy locally and avoid unsupported rules for older retained TFMs.
6. Record deliberately deferred work in the owning code's TODO or an appropriately scoped issue,
   with the reason and revisit trigger. Do not create a new tracked upgrade plan/report unless
   requested, or expose private topology in central skill references.

### 5. Validate the Outcome

- With approval, restore and build the affected solution(s) with the target SDK, all retained TFMs
  and relevant configurations. Validate Debug and Release separately when their dependency graphs
  differ; serialize builds that share outputs. Verify the published-package graph, not just local
  source substitutions.
- Run the existing lint/analyzer gates and approved focused tests. Include behavior checks for the
  relevant release-note changes; escalate only as needed. Ask separately before live/integration
  execution outside the approved scope.
- For approved performance work, compare a representative before/after workload under equivalent
  configuration and hardware. Measure the claimed metric: allocations, throughput, latency,
  startup or artifact size. State regressions and inconclusive results, not just improvements.
- Validate publish/AOT/trimming and container startup on the relevant platforms when applicable
  and authorized. Review generated SQL/migrations without applying database changes; verify
  OpenAPI/JSON contracts and frontend navigation/authentication when those surfaces changed.
- Report source/target and package changes, required fixes, implemented and deferred opportunities,
  deprecation findings, exact validation outcomes and remaining blockers. A successful restore or
  build alone is not behavioral, performance or deployment verification. Mark declined or blocked
  checks as unverified, never passing.

## Maintaining This Skill

- At each major release (.NET 12 and onward), add one short `references/net<major>.md` and a row
  above, using verified official sources. Record the checked date and release status, selected
  high-value features with codebase search cues, and notable obsoletions/breaks with replacements.
  Retain prior references while they are needed for supported or skipped-major upgrade paths.
- Recheck the .NET 11 RC2 reference at GA: remove withdrawn/renamed features, distinguish features
  still experimental, and update status and source links instead of appending contradictory notes.
- Reassess the customization-review inventory when new .NET domains/skills are added, and ensure
  release-specific guidance updates reach the relevant instructions, examples and templates.
- Refresh references when servicing releases change compatibility, provider/tool support catches
  up, support policy changes, or official documentation moves. Reverify on every use regardless
  of the recorded date; never infer .NET 12 features or URLs from .NET 11.
- Keep the workflow version-neutral and references concise. Amend existing highlights rather than
  accumulating copied release notes, benchmark claims or a second package/container/test workflow.
- Refresh the worked assessment when release status, API guidance or repository validation
  conventions change; keep its hypothetical results distinct from executed evidence.
