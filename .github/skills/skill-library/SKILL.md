---
name: skill-library
description: 'Author and validate skill metadata, preview committed inventories, build deterministic required-only ZIPs, adapt one verified ZIP into a local Spec Kit extension/catalog pilot, and prepare component versions. Use for metadata, archive or extension-pilot work. General installation and publication are not implemented.'
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
   [version-preparation workflow](#version-preparation) below. Inputs must pass the existing validator,
   including coherent exact dependency pins, before preparation; consistent already-prepared versions
   and pins are accepted when they match explicit decisions against released baselines.
3. Declare repository-wide license and shared notice defaults once in `.config/skill-library.yaml`,
   using the bundled [closed defaults schema](./repository-defaults.schema.json). The repository's
   [defaults](../../../.config/skill-library.yaml) declare `license: MIT` and `notices: [LICENSE]`.
   Omit component `license` unless genuine terms differ; component `notices` add root-relative paths
   to shared notices, never replace them. Do not repeat inherited paths. Defaults declare known terms,
   not rights clearance; never infer or relicense third-party content from the repository license.
4. Declare exact `required` edges only for real component prerequisites. Optional edges add a
   `selectionKey` and `reason`; conditional Markdown links alone do not declare dependency edges.
5. All eligible committed files beneath the skill directory are implicit archive content.
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
authored metadata. Archive building derives the exact source commit from local Git, not a sidecar
claim. Local build evidence is not an immutable release or publisher-authenticity record.

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
adjacent synthetic metadata, preparation, inventory, archive and extension suites using installed Pester 5.7.1 and the
supplied `-PythonPath`. Each suite must execute nonzero tests. The repository's existing runner also
discovers these suites; neither route installs prerequisites. Fixture Git mutations remain confined
to minimal temporary repositories, never the source repository.

The reader rejects duplicate/non-string keys, aliases/anchors, explicit tags, merges, multiple documents,
non-JSON types, nonfinite numbers and excessive nesting. Path checks reject traversal, absolute paths,
backslashes, symbolic links (including ancestors), case collisions in skill trees and conservative
secret/cache filenames. They inspect local opted-in trees, not a Git archive or privacy scan; untracked
local files are not thereby approved for packaging. The inventory preview below evaluates committed
inputs separately; packaging must still review its exact inventory and rights. Do not recurse
unconverted private skills.

There is no publication mode or legal-clearance result. Before publication, a separate future gate
must review actual rights and notice obligations against the exact committed inventory and revision,
including third-party material, and exclude unresolved content. A generated immutable provenance/release
record will capture repository/revision, derived folders and entrypoints, input paths/hashes, effective
licenses/notices, exact dependency closure and optional selections, review evidence and artifact digests.
Authored metadata, generated release evidence and consumer install inventory remain separate authorities.

## Committed Inventory Preview

Use the [read-only preview](./scripts/Invoke-InventoryPreview.ps1) to inspect eligible committed files,
dependency reasons, external instructions and effective license/notice declarations. It uses the same
installed prerequisites as validation plus local Git, and never installs tools or executes payloads.

```powershell
./.github/skills/skill-library/scripts/Invoke-InventoryPreview.ps1 `
   -SkillName patterns-ports-and-adapters `
   -OptionalSelection patterns-ports-and-adapters/module-composition `
   -PythonPath /path/to/python
```

`-RepoRoot` defaults to the invoked script's repository, independent of caller location.
`-SourceRevision` defaults to `HEAD`; it must resolve unambiguously to one locally available commit.
Dirty, staged, deleted-local and untracked files never replace committed bytes. Omitted `-SkillName`
selects all opted-in native roots; repeated roots normalize. Only reachable explicit optional choices
enter closure; duplicate choices still fail. The existing validator owns catalog-wide checks and
membership, not a second resolver or inferred Markdown links.

`ValidationRules=invoked-tool-bundle` identifies the currently invoked trusted rules, independently of
`SourceCommit`. The validator, isolated Python reader and schemas are captured separately from inert
historical files; historical tooling is never executed. Eligible regular internal files are implicit.
Only committed ancestor ignore rules apply: ignored ordinary content is omitted, while ignored selected
entrypoints, sidecars, external declarations or notices fail. Host/global excludes do not participate.
Defaults and ancestor ignore files are rule inputs, not automatically payload. Unsupported modes,
links, unsafe paths and collisions fail before source paths are materialized.

Success emits one complete JSON object after removing temporary inspection data; dot-sourcing exposes
`Invoke-SkillInventoryPreview` returning an object without exiting its host. Components/files are unique
and ordinally ordered, with every owner, reaching root and active incoming edge. Collections remain
arrays for empty and singleton results. External reasons retain
loading purpose and zero-based declaration indexes. License sources distinguish explicit overrides from
inheritance even when their values match. Failures are sanitized categories on stderr/nonzero exit, or
terminating object errors; cleanup failure suppresses success. No inventory file is created automatically.

The preview creates no archive, installation, version edit, tag, release or publication. It is not
immutable provenance, rights clearance or delivery approval. Linux synthetic validation is recorded in
the feature's validation guide; native Windows verification remains required before claiming Windows
support. Archive builds and redistribution have separate exact-content and rights review gates.

## Local Skill Archives

Use the [archive entry point](./scripts/Invoke-Archive.ps1) after approval for actual archive builds.
It requires Linux, PowerShell 7.4+, local Git and an existing CPython 3.11+ interpreter with
PyYAML 6.0.3. It does not install prerequisites. Native Windows and other Python implementations
are refused; version minima are not proof of byte equivalence across runtime versions.

```powershell
$result = ./.github/skills/skill-library/scripts/Invoke-Archive.ps1 `
   -SkillName patterns-ports-and-adapters -SourceRevision HEAD `
   -OutputDirectory /tmp/new-skill-archive -PythonPath /path/to/python | ConvertFrom-Json
$hash = (Get-FileHash -LiteralPath $result.ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -cne $result.ArchiveSha256 -or
      [IO.File]::ReadAllText($result.ChecksumPath) -cne "$hash  package.zip`n") {
      throw 'Archive integrity comparison failed.'
}
```

Exactly one explicit native folder is required. `-OptionalSelection` is not accepted. The unchanged
inventory/validation API resolves the entire required closure once; optional-only skills and their
dependencies never enter this archive. A future loader may offer related optional skills as separate
downloads, not silently add them to this artifact. Native usage and optional inventory preview remain
available independently. Dot-sourcing exposes `Invoke-SkillArchive`, returning an object without
exiting the host. Repository/interpreter defaults follow the invoked tool, not caller location.

The destination must be a new absolute directory under an existing stable trusted parent, outside
the source repository and resolved Git administrative/common directories. Existing files, empty
directories, dangling links, linked ancestry, missing parents and ambiguous path components fail.
Scratch also stays outside those boundaries. Never edit inputs or output concurrently. The writer
uses Linux descriptor-relative no-follow opens, exclusive reservation and an ownership/content ledger;
this is not protection against a hostile same-user or privileged writer.

Success returns one JSON object after scratch cleanup, writer finalization and a clean writer exit.
The new directory contains exactly `package.zip` and `package.zip.sha256`. The stored ZIP contains
`manifest.json` first, then eligible committed files under `payload/<repository-relative-path>`.
Native path geometry, blob bytes and executable modes are preserved without executing payload code.
Dirty, staged, deleted-local and untracked files never replace the frozen commit's inputs. Existing
inventory path restrictions remain authoritative; Unicode content does not imply wider filename support.

The manifest records the full source commit, root/version, required-only components, every payload's
mode/size/SHA-256/owners/reasons, effective license/notice attribution and exact trusted builder/runtime
identity. The captured invoked tool bundle is separate from historical source; only the captured
trusted code executes. `skill-archive/1` fixes ZIP headers, ordering and canonical evidence encoding.
The generated manifest has no self-hash or archive hash. The detached digest hashes the completed ZIP,
with two spaces before `package.zip` and one LF. Digests enable integrity comparison, not publisher
authentication, legal clearance or immutable release evidence. No authored versions or pins change.

Failures emit a sanitized category and nonzero exit, or a terminating object error. No artifact digest
or success object is returned on failure. Rollback removes only unchanged provably owned entries and
the matching empty directory; foreign additions, changed files, replacements and hardlinks are retained
for deliberate recovery. Cleanup/finalization failures suppress success and identify recovery paths.
Never recursively delete or automatically adopt those paths. Interruption can leave a marked or unmarked
directory that retries must refuse. Partial files can be visible: neither atomic two-file visibility
nor crash-atomic rollback is promised. The native archive writer does not install, publish or load
extensions; the separate local extension pilot is described below.

## Local Spec Kit Extension Pilot

The [Invoke-SkillExtension adapter](./scripts/Invoke-Extension.ps1) converts an approved
`skill-archive/1` build into a genuine Spec Kit 1.2.3 extension and one local catalog entry.
It consumes that archive's expected SHA-256, preserves its required-only canonical resources beneath
`resources/library/`, and adds a generated manifest, source/build evidence and thin read-only loading
command. It does not resolve dependencies again, rewrite native guidance or include optional-only skills.

```powershell
./.github/skills/skill-library/scripts/Invoke-Extension.ps1 `
   -ArchivePath /path/to/native/package.zip -ArchiveSha256 <expected-sha256> `
   -OutputDirectory /path/to/new-site -BaseUri http://localhost:8123/
```

Use an existing trusted source archive from the approved builder, not arbitrary uploaded ZIPs.
The Linux-only adapter limits source archives/total payload to 64 MiB and individual source members
to 16 MiB. Output must be a new absolute directory under an existing unlinked trusted parent outside
the source checkout. Exclusive reservation and file creation refuse existing output. After-reservation
failure retains partial output for deliberate inspection; there is no recursive rollback, retry adoption,
hostile-writer isolation or new atomicity guarantee. Preserve stable inputs and exclusive caller use.

The generated site contains `<id>-<version>.zip`, its detached `.sha256` and `catalog.json`.
Catalog locations permit HTTPS or loopback HTTP, with no embedded credentials, query or fragment.
The extension declares `==1.2.3` compatibility and `speckit.<id>.load`; Copilot skills-mode registration
renders `/speckit-<id>-load`. The command explicitly reads installed guidance and relevant resources;
copied instruction files do not acquire native `applyTo` activation. No packaged scripts execute.

The [pilot validation guide](../../../specs/003-spec-kit-extension-pilot/quickstart.md) distinguishes
real catalog discovery, exact-version installation, digest/conflict refusal and installed-byte checks
from actual editor invocation. Manual resource reads or generated command files are not proof that
Copilot discovered/invoked the command in the consumer session. A discovered command may supply its
loader as an automatic Copilot attachment; do not require a separate tool read of that loader. Confirm
native command selection rather than manual file attachment, verify installed-only guidance reads,
and distinguish owner-reported runtime evidence from independently inspected traces.
Use Spec Kit's own installer for this
pilot; general optional downloads, installer ownership/recovery, upgrades and publication remain future
work. Local catalog integrity is not publisher authentication or redistribution approval.

## Version Preparation

The [local PowerShell entry point](./scripts/Invoke-VersionPreparation.ps1) prepares all opted-in
components without packaging or Git writes. Default execution returns a JSON preview with `Ready`,
`MissingDecisions`, `SourceCommit`, baseline/target versions and baseline commits, reasons, exact
own-version/pin edits, proposed immutable tags and a `Fingerprint`. It writes no repository files;
temporary parsing material is removed. Dot-sourcing exposes `Invoke-SkillVersionPreparation`, returning
the same plan as an object rather than JSON. `-RepoRoot` and `-PythonPath` follow validation defaults.

For unpublished components, acknowledge every ID in `-BootstrapId`; retain each declared initial
version rather than inventing `0.0.0` or incrementing it. Omitted acknowledgements produce an incomplete
preview. This also covers new nonignored components not yet committed. For released components,
`-ImpactJson` maps every affected ID, including reverse consumers, to an explicit `patch`, `minor` or
`major` decision. Missing decisions produce `Ready: false` and prevent apply. Unknown IDs, inappropriate
bootstrap/impact decisions and unexplained own-version/pin drift fail rather than being overwritten.

```powershell
$script = './.github/skills/skill-library/scripts/Invoke-VersionPreparation.ps1'
$decisions = '{"example-skill":"minor","example-consumer":"patch"}'
$preview = & $script -ImpactJson $decisions -PythonPath /path/to/python | ConvertFrom-Json
$preview | ConvertTo-Json -Depth 64
# After reviewing Ready, components, reasons, edits and proposed tags:
& $script -ImpactJson $decisions -PythonPath /path/to/python `
   -Apply -ReviewedFingerprint $preview.Fingerprint
```

For an initial release, replace `-ImpactJson $decisions` with
`-BootstrapId example-skill,example-consumer` in both calls; mixed catalogs can use both parameters
for different IDs. A preview is not apply approval. `-Apply` requires the reviewed fingerprint and
recomputes the plan before any metadata mutation. Export JSON only through an explicit caller action
outside managed skill content, which itself would change the inputs. Nonzero exit means failure;
an incomplete preview is a successful read-only diagnostic, not an applicable plan.

Baselines use the numerically latest local `<stable-id>/X.Y.Z` tag, not lexical order or current
folder identity. Every matching tag must resolve to an ancestor of `HEAD` with exactly one committed
sidecar carrying that ID and matching version. Stable-ID source/native renames are detected using that
committed identity, never Git rename similarity. Noncanonical/mismatched/ambiguous tags, missing
objects, shallow or partial history, replacements, grafts, alternates and unmerged indexes fail.
Supply complete trusted local history and release refs beforehand: no network runs, and local Git
cannot prove that a tag was never moved or an unfetched tag does not exist. Tags are only proposed.

Detection compares eligible tracked and new nonignored internal content, declared external files,
defaults and inherited/additional notices against each released source. Deletions, declaration changes,
native moves and source executable-mode changes count. Version and exact-pin scalar values alone do
not count as content changes; comments, quotes and unrelated metadata remain meaningful source inputs.
Unchanged released records must still equal the released version. Prepared targets are calculated from
the baseline and explicit impact, so identical prepared content/pins do not trigger another bump.

The fingerprint binds effective raw inputs, Unix file modes, the implementation/schemas, Git refs,
`HEAD`, index, repository location, bootstrap acknowledgements and decisions. Planning checks inputs
before and after calculation; apply rechecks before writing and verifies expected inputs afterward.
All candidate metadata is rendered through the strict reader's parsed YAML scalar marks and validated
together in temporary storage before mutation. Only existing own-version and required/optional pin
scalars are writable; quoted style, comments, Unicode, CRLF and unrelated fields are preserved. Plain
or single/double-quoted version scalars are supported; block-style version scalars fail conservatively.

Apply holds metadata handles denying cooperating writers, checks original bytes and validates the
resulting library. Ordinary write/validation failures restore owned original bytes and remove temporary
storage. Unexpected concurrent bytes are never blindly restored over: preserve them and retain the
reported temporary originals for deliberate recovery, then remove that recovery directory after review.
This is not a filesystem-wide transaction, durable crash journal or protection against hostile path
replacement/noncooperating native writers. Do not edit inputs concurrently; interruption or storage
failure can require manual recovery. Windows filesystem behavior still needs native-host verification.

## Planned Release Flow

Version preparation and local archives above are implemented; PR creation and release publication remain
separate operations. Review preparation before opening a PR and rerun after changed inputs or decisions.

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
released version must fail. Local archives do not implement tag creation, publication, immutable release
snapshots, catalogs, installer ownership/recovery, Spec Kit initialization or packaged runtime discovery.

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
- Recheck inert staging, isolated trusted imports, ordinal reasons, snapshot-only ignores and cleanup when Git, Python, PowerShell or filesystem behavior changes.
- Recheck raw ZIP headers, canonical evidence, runtime fingerprints and complete-byte rebuilds when CPython's zipfile/json behavior changes; ASCII names use flag 0 and UTF-8 names use 0x0800 without private encoders.
- Keep archive capture/fixtures aligned with the complete trusted bundle, including scripts/requirements.txt; builder identity is distinct from the committed payload's source.
- Recheck Spec Kit manifest/catalog fields, exact-version/digest selection and Copilot skills registration against the pinned installed runtime; consumer fixtures need integration manifests as well as init options.
- Keep extension-adapter binary stream and dot-source parameter regressions: preserve byte arrays as single return objects and explicitly retain caller destinations when loading parameterized scripts.
- Recheck descriptor-relative exclusive reservation, immediate ownership records, fault/race cases and scratch/finalization acknowledgments when changing Linux filesystem or process behavior; cleanup failures must never produce success.
- Keep prohibited-operation tripwires self-validating and arm them after synthetic fixture setup; historical payload code stays inert, and JSON evidence comparisons must ignore object-key order while preserving array order.
- Recheck local-tag evidence, baseline decisions, fixed-point propagation and idempotence when changing preparation.
- Keep synthetic self-preparation coverage and its complete helper bundle: the component containing the writer is also an input, so post-write implementation binding must allow exactly its reviewed metadata scalar edits.
- Recheck scalar marks, input binding, cooperating-writer handles and guarded rollback on Python, Git, PowerShell or filesystem changes; local tags are not proof of remote completeness or historical immutability.
- Verify native discovery before deepening folders; keep catalog migration history and installer recovery aligned.
