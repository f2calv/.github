# ADR 0002: Agent Plugins Packaging

**Status:** Accepted; implemented, client proof pending.
**Date:** 2026-11-01.
**Scope:** Publishing the shared skills as [Agent Plugins](https://agent-plugins.org/) v1.0.0 packages
alongside the existing Spec Kit extensions. Copilot workspace and personal-link consumption is unchanged.

## Context and Problem

[ADR 0001](adr-0001-skill-library-distribution.md) packages each skill as a versioned Spec Kit
extension. That reaches Spec Kit users only. Agent Plugins is a vendor-neutral package format whose
steering committee includes Amazon, Cursor, Microsoft, OpenAI and Vercel. It lets one package load in
any conformant client.

Source-confirmed facts from the [specification](https://agent-plugins.org/specification):

- A plugin is a directory with a required root `plugin.json`. The manifest schema is closed:
  `$schema` and `name` are required; `version`, `description`, `author`, `homepage`, `repository`,
  `license`, `keywords` and `extensions` are optional.
- `name` allows 1-64 characters of `[a-z0-9.-]`, alphanumeric at both ends, with no `--` or `..`.
  Every current skill id already conforms.
- v1 has exactly two component types: skills, discovered from immediate children of `skills/`, and MCP
  servers in root `mcp.json`. Instructions, prompts, agents and hooks are not portable in v1. They may
  only live under a reverse-domain client extension directory.
- Every package path must resolve inside the plugin root, including symlinks.
- No dependency concept exists. Client-specific manifest data goes under `extensions`, keyed by
  reverse-domain namespace, and other clients ignore it.
- Distribution, installation, marketplaces and updates are client-owned and out of scope.
- Skills must conform to the [Agent Skills specification](https://agentskills.io/specification), and
  a client must skip a non-conforming skill. That specification allows only the frontmatter fields
  `name` (matching the folder), `description` (at most 1024 characters), `license`, `compatibility`,
  `metadata` (string map) and `allowed-tools`.

Observed in this repository during research:

- Every skill's `name` matches its folder, and every description is within 1024 characters.
- 40 of 49 skills use VS Code-specific frontmatter: `argument-hint`, `user-invocable`, and in two cases
  `disable-model-invocation`. A strict client, or the `skills-ref validate` reference validator, may
  therefore reject them.
- Sidecar `externalFiles` point at `.github/instructions/*.md` and are linked from `SKILL.md` as
  `../../instructions/<file>`. A plugin layout of `skills/<id>/` plus `instructions/` at the plugin
  root preserves those links and stays inside the root.
- The repository ships no MCP servers, so `mcp.json` is not needed.

Unknown: which shipping clients load Agent Plugins today, and from what sources (directory, Git
subdirectory, archive). The [compatible clients](https://agent-plugins.org/compatible-clients) page
renders client-side and was not readable during research.

## Goals and Constraints

- One source of truth. Plugins are generated from the same skill folders, sidecars and release tags as
  the Spec Kit ZIPs; no second copy is committed.
- Plugin versions equal skill versions, so one bump releases both formats.
- VS Code workspace and personal-link use keeps the current frontmatter, because VS Code reads
  `argument-hint` and `user-invocable` at the top level.
- Generated packages pass Agent Plugins and Agent Skills validation.
- Non-goals: running a marketplace, defining client install UX, and porting instructions as a component
  type.

## Options Considered

| Option | Benefits | Costs and risks | Assessment |
| --- | --- | --- | --- |
| Do nothing | No work | Non-Spec-Kit clients must clone or link the repository | Rejected; misses a standard the main vendors back |
| Commit `.github/plugin.json`, making `.github/` the plugin root | No build step; Git-installable where a client accepts a subdirectory | All-or-nothing; no per-skill version; workflows and templates sit inside the package; source frontmatter fails strict validation | Rejected as the primary path; reconsider if clients only install from Git |
| One generated plugin per skill | Mirrors the Spec Kit model; per-skill versions; minimal footprint | Required skills cannot be expressed portably; 49 packages to list | **Preferred** |
| Generated bundles per facet (for example `dotnet`, `containers`) | Fewer packages; required closures usually fall within one bundle | Bundle versions must be derived; facets overlap; boundary churn | Deferred; add when clients favour few large plugins |

## Decision

Generate one Agent Plugin per skill during the existing skill release, from the same tagged source.

```text
<id>-<version>-plugin.zip
├── plugin.json
├── LICENSE
├── skills/<id>/        # the skill folder, frontmatter normalised
└── instructions/       # sidecar externalFiles, `.github/` prefix removed
```

`plugin.json` mapping:

| Field | Source |
| --- | --- |
| `$schema` | `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json` |
| `name`, `version` | skill id and sidecar `version` |
| `description` | `SKILL.md` frontmatter |
| `repository` | `https://github.com/<owner>/<name>` of the publishing repository |
| `keywords` | sidecar `facets`, omitted when empty |
| `extensions."io.github.f2calv.skill-library"` | `required` pins and `related` ids with reasons |

`license` is omitted because the packaged `LICENSE` file is authoritative; `homepage` and `author` are
omitted until a client shows a use for them. An external file outside `.github/` fails the build,
because its relative link would escape the plugin root.

Every published skill gets a plugin, including this library's own `spec-kit-*` skills. The
`speckit-*` skills that `specify init` generates belong to Spec Kit and are excluded from validation
and packaging.

Linked instructions travel inside each plugin as plain copies, the same way the Spec Kit ZIP carries
them under `resources/.github/instructions/`. A client loads only the skill. The agent reads an
instruction file when it follows the skill's relative link; nothing applies it through `applyTo`.
Automatic `applyTo` behaviour still needs the workspace or personal-link setup. A skill that lists an
instruction in `externalFiles` gets a version bump whenever that instruction changes.

When packaging, normalise the frontmatter: keep the portable fields and move the VS Code fields into
`metadata` as strings, for example `metadata.argument-hint`. The source files stay unchanged.

Required skills remain a skill-library concern. The catalog and the bootstrap's `plan` command resolve
the closure, and the `extensions` entry records it for any client that chooses to read it.

Publish each plugin as a ZIP asset on the existing `<id>/X.Y.Z` release, and list it in the Pages
catalog as `skill_library.agent_plugin` (download URL and SHA-256) and as a link on `index.html`.
Published releases are never changed, so a release made before this decision gains no plugin; each
skill gets one on its next version.

## Consequences

- Any conformant skills client can use a skill without Spec Kit or a repository clone.
- One build produces two formats, so the same version and tag cover both. The release workflow takes
  one more packaging step and the catalog gains one URL per skill.
- Installing a plugin does not install its required skills. Users install each required plugin
  listed in the catalog or in the manifest's `extensions` entry.
- Frontmatter normalisation is a build transform. It must be tested so VS Code-only fields are never
  silently lost.
- No executable code runs at install. Skill scripts run only when an agent invokes them, as today.

## Validation and Delivery

Implemented with `skill-library` 1.1.0:

- [x] **Conformance gate.** `Test-SkillLibrary.ps1` checks each skill's normalised frontmatter
  against the Agent Skills rules; all 49 skills pass.
- [x] **Build.** `New-SkillPluginArchive` and `New-SkillPluginManifest` in `SkillLibrary.psm1`, plus
  `Build-SkillExtension.ps1 -AgentPlugin`, reuse the deterministic ZIP writer. Pester covers layout,
  link resolution, the closed manifest field set, frontmatter normalisation and byte-identical rebuilds.
- [x] **Publish.** `Publish-SkillRelease.ps1` attaches the plugin ZIP and adds it to the catalog and page.
- [x] **Manifest schema.** Every generated `plugin.json` validated against the published
  `plugin.schema.json` in a one-off local check (48 of 48). The schema is not vendored; the unit test
  asserts the closed field set instead.
- [x] **Docs.** README FAQ, [architecture](architecture.md#agent-plugins), demo 8 and the
  skill-library skill.
- [ ] **Client proof.** Load one generated plugin in a conformant client and record the client and
  version here.

## Handover

1. After merge, confirm the `skill-library/1.1.0` release has `skill-library-1.1.0-plugin.zip` and
   the Pages catalog shows `skill_library.agent_plugin` for it.
2. Run demo 8, then load the extracted folder in an Agent Plugins client; record the result above
   and drop "client proof pending" from the status.
3. Decide whether to backfill plugins for existing skill versions. It would mean rebuilding from each
   tag and adding an asset to a published release, which ADR 0001 currently forbids; the alternative
   is waiting for each skill's next bump.

## Open Questions and Reconsideration

- Which clients ship Agent Plugins support, and do they install from ZIP, Git subdirectory or a
  marketplace manifest? If Git subdirectory dominates, revisit the committed `.github/plugin.json`
  option or publish generated plugins to a branch.
- Should the source frontmatter move VS Code fields into `metadata` once VS Code reads them from there?
  That would remove the build transform.
- Would facet bundles serve users better than per-skill plugins once real install UX is known?
- Should instructions ship under a client extension directory once a client defines one for Copilot?

## Evidence and Related Decisions

| Evidence | Relevance |
| --- | --- |
| [Agent Plugins specification v1.0.0](https://agent-plugins.org/specification) | Manifest, layout, containment and extension rules |
| [Agent Skills specification](https://agentskills.io/specification) | Frontmatter fields and name rules that skills must meet |
| [Agent Plugins example](https://github.com/agentplugins/agent-plugins-example) | Reference package layout |
| [ADR 0001](adr-0001-skill-library-distribution.md) | Versioning, tags, packaging and Pages catalog this decision reuses |
| [SkillLibrary.psm1](../.github/skills/skill-library/scripts/SkillLibrary.psm1) | Packaging, frontmatter normalisation and catalog implementation |
