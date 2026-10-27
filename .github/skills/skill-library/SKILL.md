---
name: skill-library
description: 'Author and validate skill-library YAML metadata, defaults, exact dependencies and external files; own the planned component version-preparation workflow. Use for metadata adoption, validation failures or version/bump decisions; packaging, installation and publishing are not implemented.'
user-invocable: true
---

# Skill Library

Maintain one authoritative [metadata schema](./skill-metadata.schema.json) and one
`skill.metadata.yaml` sidecar per opted-in native skill. Native `SKILL.md` frontmatter still owns
discovery name and description. Metadata adds distribution identity, not another Markdown source.

## Authoring

1. Inspect the skill directory, native links and actual external prerequisites. Start from the
   [valid synthetic template](./examples/metadata.yaml.tmpl); replace its example identity.
2. Keep `id` explicit; it may differ from the aligned native folder/frontmatter name. Quote the exact
   plain `X.Y.Z` version. Keep distribution identity stable across source-folder/native-name renames
   by default; native folder/frontmatter alignment still applies. The three initial `1.0.0` values are
   unpublished authoring intent, not releases. Explicit initial versions are deliberate bootstrap
   authoring, not an automatic release. Author content and dependency intent normally, but avoid
   hand-editing own versions or required/optional version pins for release preparation; use the
   planned workflow below once implemented. Today only metadata authoring/validation is implemented.
3. Declare repository-wide license and shared notice defaults once in `.config/skill-library.yaml`,
   using the bundled [closed defaults schema](./repository-defaults.schema.json). The repository's
   [defaults](../../../.config/skill-library.yaml) declare `license: MIT` and `notices: [LICENSE]`.
   Omit component `license` unless genuine terms differ; component `notices` add root-relative paths
   to shared notices, never replace them. Do not repeat inherited paths. Defaults declare known terms,
   not rights clearance; never infer or relicense third-party content from the repository license.
4. Declare exact `required` edges only for real component prerequisites. Optional edges add a
   `selectionKey` and `reason`; conditional Markdown links alone do not declare dependency edges.
5. All eligible committed files beneath the skill directory are intended future package content.
   Do not enumerate internal references, examples, scripts or assets. There is no `resources` field.
   Declare only external repository files in `externalFiles`, with `path`, `kind` (`instruction` or
   `notice`) and `loadingPurpose`. An external declaration is required when the component is selected.
6. Declare advisory `tooling` with `id`, exact or `>=X.Y.Z` `versionRequirement`, `scope` (`build`,
   `authoring`, `consumer`) and boolean `required`. Validation does not execute or install these tools.
7. With test approval, maintain focused synthetic coverage alongside the validator. Validate metadata
   and native links separately; local links are not an inferred graph or a complete redistribution audit.

`facets`, `notices`, `required`, `optional`, `externalFiles` and `tooling` may be omitted and normalize
to empty arrays, as may repository-default `notices`. An omitted or empty component notice array adds
nothing; inherited notices still apply. Explicit nulls and wrong types fail. Repository `license` is
required; component `license` is an optional nonempty override. Unknown fields fail in every object.
The optional `$schema` is informational; validation always uses the bundled schemas and fetches no
remote references. Native `SKILL.md` and the source folder are derived, not declarations. No
`entrypoint`, `origin`, `provenanceStatus`, `schemaVersion`, hashes or resolved closure belong in
authored metadata. Packaging will derive the repository identity and exact source revision from its
verified source, not a sidecar claim.

## Local Validation

The [PowerShell entry point](./scripts/Invoke-Validation.ps1) requires PowerShell 7.4+, Python 3.11+
and the [pinned PyYAML prerequisite](./scripts/requirements.txt). The bundled
[YAML reader](./scripts/Read-Metadata.py) parses metadata and native frontmatter. Supply an existing
interpreter with PyYAML 6.0.3 through `-PythonPath` if `python3` lacks it; no setup runs automatically.

From the repository root:

```powershell
./.github/skills/skill-library/scripts/Invoke-Validation.ps1 `
  -SkillName patterns-ports-and-adapters `
  -OptionalSelection patterns-ports-and-adapters/module-composition `
  -PythonPath /path/to/python
```

`-RepoRoot` defaults to this script's containing repository regardless of caller working directory.
`-SkillName` selects native folder roots; omitted selects every opted-in skill. Discovery inspects only
immediate sidecars and skips unconverted directories. Every opted-in record is checked for schema,
native alignment, paths and declared edge availability/version. Repository defaults are mandatory and
validated even when a component overrides its license. Shared and additional notice paths use the same
containment, regular-file, link and filename checks as external files. Duplicate paths across inherited
notices, component notices and external declarations fail. Required cycles fail across the catalog.
Optional edges enter closure only when their `component-id/selectionKey` is explicitly selected and
reachable; selected optional cycles fail. Success returns catalog count and dependency-first selected IDs.
Failures return nonzero without echoing YAML contents or interpreter stderr.

After schema edits, refresh the editor's YAML schema cache if diagnostics still require removed
fields while bundled validation passes. Do not restore retired declarations to satisfy cached schemas.

After explicit test approval, the [focused test entry point](./scripts/Invoke-Tests.ps1) runs only the
adjacent synthetic suite using installed Pester 5.7.1 and the supplied `-PythonPath`. The repository's
existing runner also discovers that suite; neither route installs prerequisites.

The reader rejects duplicate/non-string keys, aliases/anchors, explicit tags, merges, multiple documents,
non-JSON types, nonfinite numbers and excessive nesting. Path checks reject traversal, absolute paths,
backslashes, symbolic links (including ancestors), case collisions in skill trees and conservative
secret/cache filenames. They inspect local opted-in trees, not a Git archive or privacy scan; untracked
local files are not thereby approved for packaging. Future packaging must use eligible committed files,
exclude ignored/untracked inputs and validate its exact inventory. Do not recurse unconverted private skills.

There is no publication mode or legal-clearance result. Before publication, a separate future gate
must review actual rights and notice obligations against the exact committed inventory and revision,
including third-party material, and exclude unresolved content. A generated immutable provenance/release
record will capture repository/revision, derived folders and entrypoints, input paths/hashes, effective
licenses/notices, exact dependency closure and optional selections, review evidence and artifact digests.
Authored metadata, generated release evidence and consumer install inventory remain separate authorities.

## Planned Release Flow

This skill owns version preparation: its workflow will orchestrate affected-component detection and
impact-based bump decisions, then delegate consistent writes to a planned deterministic local
PowerShell script under its own `scripts/` directory. Preview must show baseline/target versions,
reasons, own-version and exact-pin edits, and proposed immutable `<component-id>/X.Y.Z` tag names;
only explicit apply approval permits metadata writes. No executable bump command exists yet.

Reuse the [release-train version-decision policy](../dotnet-release-train/SKILL.md#release-version-decision),
not an assumed reusable skill-version script: major for breaking public contracts, minor for compatible
new functionality, patch for compatible fixes/internal refactoring. Verify numeric baseline versions
against immutable release history and reviewed preparation state. Require explicit decisions for
breaking or substantial changes, recording the impact and expected version; never blindly default to
patch. Independent skill versions do not use repository GitVersion or its `+semver:` commit directives.
Assess source/native-command renames for public compatibility even when distribution ID stays unchanged.

Releases will go through pull requests. Detection must include skill content, shared external files,
defaults and incorporated dependencies. Propagate through both required and optional reverse dependency
edges until a fixed point; a pin-only consumer change makes that consumer affected even when its
Markdown is unchanged. The script must compute the complete preparation before applying consistent
own-version and exact required/optional pin writes, not increment versions while traversing edges.
For example, if a PR edits skills A and B and A depends on B, A's metadata must update both its own
`version` and the required or optional exact `dependency.version` pin to B's new version. B's own
version also changes. Bump each affected component at most once per preparation, even when it is
both directly edited and reached through propagation. Reruns against the same preparation must be
idempotent, not repeatedly bump versions; changed inputs or decisions require a refreshed preview.

Optional release propagation is independent of install-time optional selection; unselected optional
edges still propagate release changes. Required cycles and cycles involving selected optional edges
still fail under the existing runtime closure rules; this release contract does not change them.

Only after merge and required checks pass will separately authorized release tooling create tags on
the verified merged default-branch commit, never the feature head. Retain the top-level `version` for
human-readable inspection and debugging: it declares release intent before publication. The immutable
`<component-id>/X.Y.Z` tag identifies the released commit; the release gate must reject any mismatch
between that tag and the committed metadata version. The generated exact-inventory record
must bind that commit, reviewed rights evidence and artifact hashes; changed inputs at an unchanged
released version must fail. No bump helper, packaging, tags, publication, immutable snapshots, catalogs,
installer ownership/recovery, Spec Kit initialization or packaged runtime discovery is implemented here.

## Planned Identity Evolution

Source paths/native names and release IDs are separate. Current discovery remains flat, inspecting
immediate skill-folder sidecars only. Future directory deepening requires verified native-host discovery
and supporting tooling; do not assume nested skills work. Native source compatibility shims are not
required, but actual breaking distribution-ID changes require one authoritative versioned migration
history in the library catalog, not installer/extension alias lists or retired source shims.

The [ADR migration contract](../../../docs/adr-0001-copilot-spec-kit-distribution.md#identity-and-migration-history)
defines version-scoped transitions, immutable history and installer safeguards. Preserve old releases,
tags and catalog entries; never reassign retired IDs to unrelated content. A stable-ID source rename
needs no ID migration, but still needs version-impact review and safe installed-path handling.

## Maintaining This Skill

- Recheck draft 2020-12 behavior when PowerShell's `Test-Json` or JsonSchema.Net changes.
- Recheck node/tag handling and scalar preservation when updating PyYAML or Python.
- Extend focused negative cases when dependency selection, filesystem link behavior or schema fields change.
- Keep repository defaults, component overrides and additive notice checks aligned without treating declarations as rights clearance.
- Reconcile the implicit-directory contract with committed-file inventory and rights evidence before packaging.
- Recheck version-preparation ownership, baseline decisions and idempotence when implementing the writer.
- Verify native discovery before deepening folders; keep catalog migration history and installer recovery aligned.
