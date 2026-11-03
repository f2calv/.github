# ADR 0003: APM Distribution

**Status:** Proposed.
**Date:** 2026-11-03.
**Scope:** Making the shared skills installable with [APM](https://github.com/microsoft/apm) (Agent
Package Manager), and which parts of the [ADR 0001](adr-0001-skill-library-distribution.md) Spec
Kit route and the [ADR 0002](adr-0002-agent-plugins-packaging.md) Agent Plugins packaging APM could
replace. Copilot workspace and personal-link consumption is unchanged.

## Context and Problem

ADR 0001 publishes each skill as a versioned Spec Kit extension, installed by the `skill` bootstrap,
which resolves required skills and copies guidance into `.github/`. ADR 0002 adds an Agent Plugins
ZIP to the same release. Two gaps remain from ADR 0002: Agent Plugins has no dependency field, so
required skills live under our own `io.github.f2calv.skill-library` manifest extension that no
client reads, and no client has yet loaded a generated plugin.

APM is Microsoft's open-source (MIT) dependency manager for agent content. Source-confirmed facts,
checked against v0.35.0 (released 2026-10-22):

- A consumer declares packages in [`apm.yml`](https://microsoft.github.io/apm/reference/manifest-schema/)
  and APM pins the resolved graph in [`apm.lock.yaml`](https://microsoft.github.io/apm/reference/lockfile-spec/):
  commit SHA, resolved ref, deployed files and their SHA-256 hashes. `apm install --frozen` replays it.
- [Dependencies](https://microsoft.github.io/apm/consumer/install-packages/) are Git references from
  any host, including a virtual subdirectory path into a monorepo with a `#ref`, single-file
  `.instructions.md` references and local paths. Dependencies resolve transitively.
- A package is recognised by its [layout](https://microsoft.github.io/apm/reference/package-types/):
  `apm.yml` with `.apm/`, a root `SKILL.md` (optionally with `apm.yml`), `skills/<name>/SKILL.md`,
  a Claude plugin, or an Agent Plugins v1 `plugin.json`, which Copilot CLI 1.0.81 or later loads
  live from `apm_modules/`.
- For the `copilot` [target](https://microsoft.github.io/apm/reference/targets-matrix/), skills
  deploy to `.agents/skills/` and instructions to `.github/instructions/`. `apm uninstall` deletes
  only files recorded in the lockfile.
- Installs scan content for hidden Unicode and block critical findings; organisations can enforce
  an [`apm-policy.yml`](https://microsoft.github.io/apm/enterprise/policy-reference/). There is no
  package signing.
- `apm pack --format agent-plugin` [builds](https://microsoft.github.io/apm/producer/pack-a-bundle/)
  an Agent Plugins bundle but fails when the package contains instructions, and APM copies `SKILL.md`
  byte for byte.
- A [marketplace](https://microsoft.github.io/apm/producer/publish-to-a-marketplace/) block in a root
  `apm.yml` lists packages by source path and can emit a Copilot CLI `marketplace.json`. Per-package
  [versioning](https://microsoft.github.io/apm/producer/versioning-strategies/) uses a
  `tag_pattern`; [`tag_pattern.py`](https://github.com/microsoft/apm/blob/main/src/apm_cli/marketplace/tag_pattern.py)
  accepts `{name}/{version}`, but does not infer it, so it must be declared.
- The format is [OpenAPM v0.1](https://microsoft.github.io/apm/specs/openapm-v01/), a Working Draft
  with no backward-compatibility guarantee before 1.0. Registries and marketplace authoring are
  [experimental](https://microsoft.github.io/apm/reference/experimental/) flags.
- Issue [#3071](https://github.com/microsoft/apm/issues/3071), open since 2026-09-24, reports that a
  monorepo subdirectory package declaring another subdirectory of the same repository as a `git:`
  plus `path:` dependency fails from 0.29.1. Issues
  [#872](https://github.com/microsoft/apm/issues/872), [#1822](https://github.com/microsoft/apm/issues/1822)
  and [#2319](https://github.com/microsoft/apm/issues/2319) on monorepo installs and tag patterns
  are closed.

Observed in a disposable container with APM 0.35.0 and this repository unchanged:

```text
apm install "f2calv/.github/.github/skills/docs-adr#docs-adr/1.0.2" --target copilot
```

- The `<id>/X.Y.Z` tag resolved: APM splits a reference at its last `#`. The lockfile recorded
  `resolved_ref: docs-adr/1.0.2`, the commit SHA, `package_type: claude_skill` and per-file hashes.
- The skill was deployed to `.agents/skills/docs-adr/`.
- Its required skill, `repository-privacy` 1.1.0, was not installed, and the lockfile recorded
  `version: unknown`: APM does not read `skill.metadata.yaml`.
- Its `externalFiles`, `markdown.instructions.md` and `markdown.mermaid.instructions.md`, were not
  installed, so the skill's `../../instructions/` links do not resolve.

Pilot, with a hand-maintained [`docs-adr/apm.yml`](../.github/skills/docs-adr/apm.yml) at 1.0.3,
installed in a disposable container from a local mirror of this repository. `GITHUB_HOST` pointed APM
at the mirror and a local stand-in served the GitHub Contents API, so github.com was not involved:

- `docs-adr` installed as a `hybrid` package and the lockfile recorded `version: 1.0.3`.
- The required skill `repository-privacy` installed transitively at `repository-privacy/1.1.0`.
  Same-repository dependencies in the shorthand string form therefore resolve; #3071 concerns the
  `git:` plus `path:` object form.
- Both instruction files installed into `.github/instructions/`, where Copilot applies them through
  `applyTo`. Single-file dependencies are fetched through the Contents API, not Git.
- The skill's `../../instructions/` links do not resolve from `.agents/skills/docs-adr/`.
- `apm.yml` and `skill.metadata.yaml` are deployed into `.agents/skills/docs-adr/` alongside the skill.
- `apm uninstall` removed all four packages and every deployed file.

Spec Kit is not mentioned anywhere in the APM documentation.

## Goals and Constraints

- **R1** One source of truth: any APM metadata is generated from the sidecar and checked for drift,
  never edited by hand.
- **R2** Versions and tags unchanged: APM resolves the existing `<id>/X.Y.Z` tags.
- **R3** Installing a skill with APM installs its required skills at their pinned versions.
- **R4** A skill's linked instructions arrive with it and its relative links resolve, or the gap is
  documented.
- **R5** Spec Kit users, VS Code workspace use and the Agent Plugin ZIPs keep working.
- Non-goals: running an APM registry, publishing to a third-party marketplace, and making APM a
  requirement for any consumer.

## Options Considered

| Option | Benefits | Costs and risks | Assessment |
| --- | --- | --- | --- |
| Keep the current design, without mentioning APM | No work | APM users find the working route by accident and miss its gaps | Rejected; the route already works and should be documented honestly |
| Document the bare APM route | Free today; pinned, hashed, uninstallable installs | No required skills, no instructions, `version: unknown` | **Proposed, phase 1** |
| Generate a per-skill `apm.yml` from the sidecar | Required skills resolved by a real client (R3); APM sees versions and descriptions; `x-` keys can carry facets, related skills and external files | A second generated file per skill; ties the sidecar mapping to a 0.x schema; skill links to instructions still break (R4) | **Proposed, phase 2**, piloted on `docs-adr` |
| Root `apm.yml` marketplace with `tagPattern: "{name}/{version}"` | `apm install <id>@<marketplace>`, semver ranges, Copilot CLI marketplace output that could give ADR 0002 its client proof | Experimental flag; another generated file; overlaps the Pages catalog | Deferred until marketplace authoring is stable |
| Replace the Agent Plugin builder with `apm pack --format agent-plugin` | Less code to maintain | Rejects packages with instructions; does not strip VS Code-only frontmatter, so strict clients may skip the skill | Rejected |
| Replace the Spec Kit bootstrap with APM | One install tool; lockfile, hashes, policy and audit | 0.x format without compatibility guarantees; drops Spec Kit users; skills land in `.agents/skills/` | Rejected now; reconsider at APM 1.0 |

## Proposed Decision

Treat APM as an additional consumer of the existing releases, not a replacement for either format.

1. **Phase 1, documentation.** Document
   `apm install f2calv/.github/.github/skills/<id>#<id>/X.Y.Z` in the Spec Kit guide and the README
   FAQ as a supported route, stating that it installs only the named skill, into `.agents/skills/`,
   without its required skills or linked instructions.
2. **Phase 2, per-skill manifest.** `docs-adr` carries a hand-maintained pilot `apm.yml`. Once the
   gate below passes, generate `.github/skills/<id>/apm.yml` for every skill from
   `skill.metadata.yaml` and `SKILL.md` (illustrative):

   ```yaml
   name: docs-adr
   version: 1.0.2
   description: <SKILL.md description>
   dependencies:
     apm:
       - f2calv/.github/.github/skills/repository-privacy#repository-privacy/1.1.0
       - f2calv/.github/.github/instructions/markdown.instructions.md#docs-adr/1.0.2
   x-skill-library:
     facets: [documentation, architecture]
     related:
       - id: github-issues-and-pull-requests
         reason: Publish or track an ADR as a GitHub issue.
   ```

   `New-SkillMetadata.ps1` and `Set-SkillVersion.ps1` would write it. Already in place for the pilot:
   `Test-SkillLibrary.ps1` fails when an `apm.yml` name, version or dependency list differs from the
   sidecar, and the Spec Kit ZIP and Agent Plugin packaging exclude `apm.yml`. The sidecar stays
   authoritative because both builds read it and `apm.yml` is a 0.x format.
3. **Unchanged.** The Spec Kit bootstrap, the Agent Plugin ZIPs and the Pages catalog stay as they
   are. The `io.github.f2calv.skill-library` plugin extension keeps describing required skills for
   Agent Plugins clients.

**Phase 2 gate:** after `docs-adr/1.0.3` is released, `apm install` of
`f2calv/.github/.github/skills/docs-adr#docs-adr/1.0.3` from github.com installs `repository-privacy`
and both instruction files, matching the local pilot (R3, R4 apart from the broken links).

## Consequences

- APM users get pinned, hashed, cleanly uninstallable skills today, with documented gaps; after
  phase 2 they also get required skills.
- APM users need no Spec Kit. Spec Kit users are unaffected.
- Skills installed by APM land in `.agents/skills/`, so a workspace that also uses the Spec Kit
  bootstrap may hold two copies of a skill. The documentation recommends one route per workspace.
- Phase 2 adds one generated file per skill and couples the build to a draft schema. Because the
  sidecar stays authoritative, a breaking APM change costs a generator update, not a migration.
- An `apm.yml` change alters the skill folder, so it needs the usual version bump through
  `Set-SkillVersion.ps1`. Until the generator exists, a bump or pin cascade fails
  `Test-SkillLibrary.ps1` until the pilot `apm.yml` is edited to match.
- Linked instructions apply through `applyTo` in `.github/instructions/`, but a skill's
  `../../instructions/` links do not resolve from `.agents/skills/<id>/`, so an agent following one
  finds nothing. APM does not rewrite links.

## Validation and Delivery

- [ ] **Phase 1 docs.** The Spec Kit guide and README FAQ describe the APM route and its gaps,
  backed by the observed 0.35.0 install above.
- [x] **Phase 2 pilot.** `docs-adr/apm.yml`, the `Test-SkillLibrary.ps1` drift check and the
  packaging exclusion, with Pester coverage. Installed with APM 0.35.0 from a local mirror: required
  skill and both instructions installed, uninstall clean.
- [ ] **Phase 2 gate.** The same install from github.com once `docs-adr/1.0.3` is released.
- [ ] **Phase 2 build.** The generator for every skill, with Pester coverage for dependency pins,
  instruction references and `x-skill-library` keys.

## Open Questions and Reconsideration

- Do Copilot clients other than Copilot CLI load skills from `.agents/skills/`? If not, an APM
  install is only useful to APM-aware agents.
- How should skills link to instructions so the link survives both the `.github/skills/` and the
  `.agents/skills/` layouts? Options include linking by URL or accepting `applyTo` as the only path.
- Reconsider replacing the Spec Kit bootstrap when OpenAPM reaches 1.0, and the marketplace option
  when marketplace authoring leaves experimental.
- If an APM marketplace becomes the main discovery route, decide whether the Pages catalog remains.

## Evidence and Related Decisions

| Evidence | Relevance |
| --- | --- |
| [APM repository](https://github.com/microsoft/apm) and [documentation](https://microsoft.github.io/apm/) | Package model, CLI and release cadence |
| [Manifest schema](https://microsoft.github.io/apm/reference/manifest-schema/) | `apm.yml` fields, dependency forms and `x-` vendor keys |
| [Lockfile specification](https://microsoft.github.io/apm/reference/lockfile-spec/) | Pinning, hashes and frozen installs |
| [Package types](https://microsoft.github.io/apm/reference/package-types/) | Skill, plugin and Agent Plugins layouts |
| [Targets matrix](https://microsoft.github.io/apm/reference/targets-matrix/) | `.agents/skills/` and `.github/instructions/` deployment for Copilot |
| [Versioning strategies](https://microsoft.github.io/apm/producer/versioning-strategies/) and [`tag_pattern.py`](https://github.com/microsoft/apm/blob/main/src/apm_cli/marketplace/tag_pattern.py) | Per-package tags and `{name}/{version}` support |
| [OpenAPM v0.1](https://microsoft.github.io/apm/specs/openapm-v01/) | Working Draft status and compatibility posture |
| [Issue #3071](https://github.com/microsoft/apm/issues/3071) | Same-monorepo regression in the `git:` plus `path:` form; the pilot's shorthand form is unaffected |
| [docs-adr/apm.yml](../.github/skills/docs-adr/apm.yml) | Hand-maintained phase 2 pilot |
| [ADR 0001](adr-0001-skill-library-distribution.md) | Tags, sidecar and Spec Kit route that APM consumes |
| [ADR 0002](adr-0002-agent-plugins-packaging.md) | Agent Plugin packaging that stays unchanged |
| [SkillLibrary.psm1](../.github/skills/skill-library/scripts/SkillLibrary.psm1) | Generator, packaging and drift checks phase 2 would extend |
