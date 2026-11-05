# ADR 0005: NuGet Package Skills

**Status:** Proposed.
**Date:** 2026-11-04.
**Scope:** Whether and how to deliver skills inside NuGet packages, both for this repository's
skill library and for skills whose subject is one of the owner's own published .NET libraries.
The existing Copilot, Spec Kit and Agent Plugin routes are unchanged.

## Context and Problem

[ADR 0001](adr-0001-skill-library-distribution.md), [ADR 0002](adr-0002-agent-plugins-packaging.md)
and [ADR 0003](adr-0003-apm-distribution.md) distribute the skills from this repository through
Spec Kit extensions, Agent Plugin packages and, proposed, APM. The .NET team now describes a further
route: [Delivering Skills in NuGet packages](https://devblogs.microsoft.com/dotnet/delivering-skills-in-nuget-packages/)
(2026-11-03). Its central argument is that a skill describing a library is most accurate when it
ships in the same package version as the API it describes, because models know little about new
or long-tail packages.

Source-confirmed facts:

- Package skills use the plain [Agent Skills](https://agentskills.io/specification) format; NuGet
  adds no new package type or manifest field. A package carries each skill at
  `skills/<package-id>-<skill-name>/SKILL.md`, per the
  [dotnet-package-skills README](https://github.com/NuGet/Client.Tools/tree/main/dotnet-package-skills).
  [Markout 0.40.1](https://www.nuget.org/packages/Markout/0.40.1) on nuget.org ships five, checked
  by listing the package's entries.
- `dotnet restore` extracts the skills into the NuGet global-packages folder with the rest of the
  package, and `project.assets.json` lists them. Agents do not scan that folder.
- [`dotnet-package-skills`](https://www.nuget.org/packages/dotnet-package-skills), a Microsoft global
  tool at `0.1.0-beta`, closes the gap: `install` copies the bundled skills of a project's **direct**
  dependencies into `.agents/skills/` (or `--destination`), records them in
  `.dotnet-package-skills.json`, refreshes them when a package version changes, and reports skills of
  packages the project no longer references for `uninstall --stale`. It accepts exact versions only,
  and skips colliding skill names with an error.
- [`dotnet-inspect`](https://www.nuget.org/packages/dotnet-inspect) lists and prints the skills in a
  package or in a project's dependencies without copying them.
- The NuGet MCP server does not yet surface package skills; the post says that work is planned.
- The post treats package markdown read by agents as a new supply-chain threat vector: consumers
  should only use packages from maintainers they trust.

Observed in this repository: five skills describe APIs that the owner's public `CasCap.Common.*`
NuGet packages implement, so their accuracy depends on a package version rather than on this
repository:

| Skill | Package API it describes |
| --- | --- |
| [dotnet-leadership-election](../.github/skills/dotnet-leadership-election/SKILL.md) | Redlock leadership in `CasCap.Common.Caching` |
| [dotnet-redis](../.github/skills/dotnet-redis/SKILL.md) | Cache-aside through `CasCap.Common.Caching` |
| [dotnet-cron-scheduling](../.github/skills/dotnet-cron-scheduling/SKILL.md) | `CoalescingScheduleRunner` in `CasCap.Common.Services` |
| [dotnet-exceptions](../.github/skills/dotnet-exceptions/SKILL.md) | The shared domain exception base, namespace `CasCap.Common.Exceptions`, in `CasCap.Common.Extensions` |
| [dotnet-logging](../.github/skills/dotnet-logging/SKILL.md) | Request-logging and default helpers in `CasCap.Common.Hosting.AspNetCore` |

Each of these mixes general .NET guidance with package-specific API detail.

Unknown: whether `dotnet-package-skills` copies a skill whose frontmatter carries fields outside
the Agent Skills set, such as `argument-hint` and `user-invocable`; whether it can follow transitive
dependencies; how a package ID containing dots maps to a skill folder name, which Agent Skills limits
to `[a-z0-9-]`; and whether VS Code Copilot loads skills from `.agents/skills/` as well as
`.github/skills/`.

## Goals and Constraints

- **N1** A skill about one of the owner's libraries is correct for the package version the consumer
  references.
- **N2** One source of truth per rule: package-resident guidance does not duplicate a central skill.
- **N3** No new dependency for consumers who do not use .NET, and no change to the existing routes.
- **N4** Packaged skills pass Agent Skills validation and carry nothing a consumer must not read.
- Non-goals: publishing NuGet packages whose only content is skills, and running a NuGet feed.

## Options Considered

| Option | Benefits | Costs and risks | Assessment |
| --- | --- | --- | --- |
| Keep the current routes only | No work | Package-specific guidance can drift from the version a consumer runs | Rejected for package-specific guidance; kept for everything else |
| One skills-only NuGet package carrying the whole library | One `PackageReference` | Only reaches repositories with a .NET project; puts Terraform, Markdown and GitHub skills in a .NET dependency graph; `dotnet-package-skills` copies only skills, not linked instructions; skills stop matching the code they guide | Rejected |
| One skills-only NuGet package per skill | Per-skill versions; NuGet dependencies could express required skills | 55 packages on nuget.org; the tool copies only direct dependencies, so required skills would not arrive; duplicates the Spec Kit, Agent Plugin and APM routes | Rejected |
| Ship package-specific skills inside the owner's own libraries | Guidance versions with the API (N1); restored with the package the consumer already references; no new package | Splits guidance between this repository and the library repositories; the library release pipeline must validate skills; depends on a beta tool for discovery | **Proposed** |

## Proposed Decision

Use NuGet only for guidance that describes a specific package's API, and ship that guidance inside
the package that implements it. Keep every other skill on the existing routes.

1. **Split by subject.** For each skill in the table above, the package-specific part (types,
   registration, options, failure modes of that version) moves into a skill shipped in the library's
   package. The central skill keeps the package-independent part (when to use leader election,
   cache-aside or coalescing schedules, and how to design around them) and links to the package skill
   by name rather than repeating it (N2).
2. **Package layout.** The library project packs each skill folder with standard `Pack` and
   `PackagePath` item metadata to `skills/<skill-name>/`, following the `<package-id>-<skill-name>`
   naming convention once the dotted-ID question is answered. Its frontmatter uses only Agent Skills
   fields (N4), and the library's CI validates it before packing.
3. **Consumption.** Consumers run `dotnet-package-skills install` after restore, or let an agent use
   `dotnet-inspect`. The central skills mention the command where they link to a package skill.
4. **Pilot first.** Move one skill's package-specific guidance into one package, release it, and
   install it in a consumer before splitting the others.

## Consequences

- Package-specific guidance can no longer drift from the package version a consumer references, and
  each library release can update its skill.
- Guidance for one topic lives in two places, linked by name. Changing an API now means updating the
  package skill in the library repository, not this one.
- Consumers who do not run `dotnet-package-skills` or `dotnet-inspect` see only the central skill,
  which still names the package skill, so they lose detail but not correctness.
- Every library release that carries a skill needs the same frontmatter and content checks as this
  repository, and a reviewer for agent-facing text.
- Discovery depends on a beta tool; if it changes or stalls, the skills stay readable in the NuGet
  cache and through `dotnet-inspect`.

## Validation and Delivery

- [ ] **Unknowns resolved.** Record how `dotnet-package-skills` treats non-Agent-Skills frontmatter,
  transitive dependencies and dotted package IDs, and whether VS Code reads `.agents/skills/`.
- [ ] **Pilot.** One package-specific skill packed into one `CasCap.Common.*` package, validated in its
  CI and released.
- [ ] **Consumer proof.** `dotnet-package-skills install` in a consumer copies the pilot skill, and an
  agent session uses it; record the tool and package versions here.
- [ ] **Central skill trimmed.** The matching central skill keeps only package-independent guidance
  and links to the package skill, with its version bumped.
- [ ] **Rollout decision.** Decide whether the other four skills follow, based on the pilot.

## Open Questions and Reconsideration

- If `dotnet-package-skills` reaches a stable release with transitive support, or the NuGet MCP server
  surfaces package skills, consumption gets simpler; revisit step 3.
- If Copilot or another client starts reading skills directly from the NuGet cache, the copy step
  disappears.
- If a library's skill and its central counterpart keep needing coordinated changes, consider moving
  the whole skill into the package and retiring the central one.

## Evidence and Related Decisions

| Evidence | Relevance |
| --- | --- |
| [Delivering Skills in NuGet packages](https://devblogs.microsoft.com/dotnet/delivering-skills-in-nuget-packages/) | Rationale, package layout, discovery tools and threat note |
| [dotnet-package-skills README](https://github.com/NuGet/Client.Tools/tree/main/dotnet-package-skills) | Skill path convention, install, list and uninstall behaviour |
| [dotnet-package-skills on nuget.org](https://www.nuget.org/packages/dotnet-package-skills) | Tool and its prerelease status |
| [Markout 0.40.1](https://www.nuget.org/packages/Markout/0.40.1) | Real package carrying skills under `skills/` |
| [Agent Skills specification](https://agentskills.io/specification) | Frontmatter fields and name rules for packaged skills |
| [ADR 0002](adr-0002-agent-plugins-packaging.md) | Frontmatter normalisation already used for portable packages |
| [ADR 0003](adr-0003-apm-distribution.md) | Parallel investigation of APM, with the same `.agents/skills/` landing folder |
