# ADR 0001: Local-First Copilot and Spec Kit Distribution

**Decision Status:** The owner selected the single-command library experience and demo deliverables on 2026-10-29. Broader lifecycle capabilities remain deferred.
**Implementation Status:** In Progress. The bounded workspace installer foundation has a passing 366-test baseline and ten passing focused PR-review checks. The shared command, bootstrap extension and per-skill CI delivery remain unimplemented; foundation acceptance is not demo acceptance.
**Date:** 2026-10-26.
**Last Updated:** 2026-10-29.
**Scope:** Optional distribution of selected native customizations as independently versioned Spec Kit extensions with dependency-aware installation.

## Context and Problem

The [native library contract](../.github/copilot-instructions.md#setup) supports workspace and
profile-linked consumption of the canonical instruction and skill folders. Selective, versioned
distribution must not require existing consumers to migrate or maintain a second Markdown source.
Library maintainers and selective consumers are the pilot audiences. The required consumer experience
is one library command with arguments, comparable to a CLI command tree, not a separate command to
learn for every skill. The earlier per-extension loading pilot proves runtime integration only.

Initial source inspection at commit `a161439e9696211c34c5a468a7811f8944c111da` recorded
the following historical baseline; subsequent preparation is recorded under [Handover](#handover).
Source links below follow the current locations, not paths at that historical revision:

* The root [MIT license](../LICENSE) and its holder notice already exist. Retain them unchanged;
  the copyright and permission notice must accompany copies or substantial portions.
* [Ports and adapters](../.github/skills/patterns-ports-and-adapters/SKILL.md), its
  [boundary reference](../.github/skills/patterns-ports-and-adapters/references/boundary-contracts.md) and
  [provider example](../.github/skills/patterns-ports-and-adapters/examples/provider-substitution.md)
  supply resource-bearing native architecture guidance. Ordinary links are not dependency declarations.
* No local `.specify/`, `specs/`, `.config/spec-kit/` or `.scripts/spec-kit/` exists at inspection.
  Existing native guidance is not evidence of Spec Kit adoption, dogfooding or packaged consumption.
* The approved [release rule](../.github/instructions/github.instructions.md#releases), subsequently
  committed with this proposal in `b22550b`, permits independently versioned non-Action monorepo
  components to use immutable `<component-id>/X.Y.Z` tags, without `v` prefixes or floating aliases.
  This policy approval authorizes no tag creation, push or release.

Prior source research targets Spec Kit `1.2.3` at
`5ea8b1cf0a38699340a38e00d02770308997d8c0`. Its
[extension implementation](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/extensions/__init__.py)
supports manifest-bearing payload trees, while the
[preset manifest](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/presets/_manifest.py)
does not establish an arbitrary `provides.files` installer. These are pinned source findings from
prior research, not generated-extension runtime acceptance or a claim about later releases.

## Goals and Constraints

* Preserve native frontmatter, `applyTo`, workspace/profile use and discovery; coordinate any approved
  naming changes across folders, skill names, links, resources and invocation.
* Author Markdown once; generate wrappers and payload copies only as build outputs.
* Package one explicit skill root and its complete required resource closure. Offer related optional
  skills separately through explicit selection, never as optional-only payloads in that archive.
* Version each component independently, recording exact inputs, dependency snapshots and SHA-256.
* Demonstrate CI-driven independent skill versioning and installable versioned artifacts, not only
  repository GitVersion or local version preparation.
* Install one library extension, then use its shared command to discover, install and load multiple
  skill extensions with required resources and explicitly selected optional additions.
* Keep setup, tests, initialization, commits, pushes, tags and publication behind separate approvals.

Mandatory whole-library format migration, global instruction injection, automatic rights clearance
and immediate automation extraction are non-goals; coordinated naming changes are a separate choice.
Separately approved container preparation is complete;
this proposal itself authorizes no further setup, tests, initialization or publication.

## Options Considered

| Option | Benefits | Costs and risks | Assessment |
| --- | --- | --- | --- |
| Keep native consumption only | No new tooling or migration | No exact component snapshots or release demo | Retain as a fully supported route, but insufficient alone |
| Maintain a second categorized source tree | Simple packaging layout | Duplicated guidance and broken native paths | Reject |
| Use upstream presets as arbitrary file installers | Appears to reuse a package mechanism | Pinned contract does not establish that behavior | Reject for resource-bearing capabilities |
| Generate extensions from explicit local closure | One source, selective artifacts, auditable inputs | Requires resolver, snapshot and runtime validation | Recommend |
| One library command with arguments | Scalable discovery, installation and loading; reuses the packaging graph | Requires bootstrap packaging, argument handling and bounded approval | Owner-selected demo interface; implementation pending |
| One public command per skill | Simple isolated pilot and direct loading | Command proliferation does not scale to a large library | Retain historical evidence, reject as the target consumer interface |
| Generate Agent Plugins from the same source | Alternative or additional client packaging | Different manifest and discovery contract | Evaluate; no second packager implemented |
| Require hosted workflows or OCI first | Central automation and transport | Setup and release-train cost before proving the contract | Defer |

## Decision and Delivery Boundary

### Foundation Close-Off and Demo Scope

The owner selected completion of the bounded installer foundation first, then clarified the required
demo experience on 2026-10-29. Close and merge that foundation as a PR before implementing the shared
command and CI delivery. Do not equate its passing tests with completion of those new deliverables.
Native consumption remains supported and unchanged.

The [extension pilot](../specs/003-spec-kit-extension-pilot/quickstart.md) completed real generation,
catalog discovery, installation and owner-reported editor loading. The
[bounded installer](../specs/004-bounded-workspace-installer/quickstart.md#real-runtime-demo)
adds preview-bound local installation, separate optional packages and retained failure evidence.
Its authoritative acceptance record distinguishes automated, real-runtime and editor observations.
The current PR may close foundation implementation while its unobserved per-extension editor gate
remains explicitly pending; the shared-command demo must earn its own fresh consumer evidence.

The demo deadline is Monday 2026-11-02 at 13:00 in the owner's local time. No timezone is inferred.
The five required outcomes are:

| ID | Deliverable | Observable acceptance |
| --- | --- | --- |
| D1 | Consolidated repository structure | Show the prefixed canonical skill names and resource layout, preserving native discovery and one authored source. |
| D2 | Metadata per demonstrated skill | Show independent ID/version, facets, required/optional edges, external instructions and notices without duplicating generated provenance. |
| D3 | CI-driven skill versioning | Change one skill and then multiple skills; CI identifies affected components, produces or validates reviewed own-version/dependency-version edits and emits matching versioned artifacts. Unrelated skills do not bump; repeated runs do not bump again. |
| D4 | Library bootstrap | Install one genuine `skill-library` Spec Kit extension into a compatible consumer and discover `/speckit-skill-library`. |
| D5 | Multiple skill extensions through the library | Search/select and install multiple independent skill extensions through that command, then load their installed guidance through the same command. Verify required resources, explicit optional consent and absence of source/profile fallback. |

Per-skill CI integration and the shared installation/loading command are required follow-on work, not
deferred roadmap items. The current [CI entry point](../.github/workflows/ci.yml) versions the repository
and runs [library tests](../.github/workflows/_skills-library-tests.yml); it does not yet version or
publish individual skills. Local version preparation is reusable implementation, not evidence that D3
has run. The bootstrap must package or explicitly provide its executable backend, trusted catalog and
prerequisites; it must not conceal a dependency on the maintainer's source checkout or temporary paths.

Persistent install pins, `upgrade-all`, individual upgrade/uninstall, renamed-ID migration, profile
installs, automatic rollback/resume, cross-platform expansion, signing, generalized public catalog
hosting and an install/upgrade-across-two-releases demonstration are deferred. They are not demo gates.
CI artifact delivery for the selected demo packages is not deferred; broad publication infrastructure
is. Any chosen distribution still requires exact-inventory rights/privacy clearance and applicable
notices before publishing those artifacts. Local digests prove integrity, not publisher authentication
or redistribution rights.

Close the current Spec Kit dogfooding implementation exercise at this foundation boundary without
fabricating completion of its remaining editor observation. Continue directly against D1-D5 with
focused implementation and validation; no further specify/plan/tasks cycle is required. Spec Kit
remains the extension runtime, not a mandatory development ceremony for the remaining demo work.

### Published Archive Retention

On 2026-10-30 the owner required indefinite availability of every published extension archive,
including superseded versions. Expiring Actions artifacts are build handoff only, never the permanent
installation source. Publishing a newer version must not delete, overwrite or expire older archives,
their checksums, exact-version catalog records or associated source/provenance evidence. Preserve
immutable `<component-id>/X.Y.Z` tags without floating aliases.

GitHub Release assets are the recommended primary ZIP transport, distinct from Actions artifacts.
Use [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
to lock assets and tags: assemble and verify every asset on a draft before publishing. Release
publication, immutable-release configuration and remote installer acquisition are not implemented by
the current artifact-only workflow or bundled-catalog installer.

Permanent retention requires no automated release cleanup and an independent retained backup of the
actual ZIP bytes, catalogs, checksums and evidence, with verified restoration. Git history alone does
not back up attached release assets. No hosting provider guarantees literal perpetual service;
repository/account deletion, service loss or mandatory removal remain availability risks. Backup and
recovery arrangements must be established before claiming the retention requirement is met. A package
registry may be evaluated as an alternative transport, but does not itself satisfy this requirement.

### Single Library Command

Use the canonical name `/speckit-skill-library` with deterministic argument parsing and a CLI-style
command tree. The following is the selected interface direction, not a claim that commands exist:

```text
/speckit-skill-library
/speckit-skill-library search architecture
/speckit-skill-library architecture
/speckit-skill-library install patterns-monolith-modular
/speckit-skill-library install patterns-monolith-modular --version 1.0.0
/speckit-skill-library list --installed
/speckit-skill-library load patterns-monolith-modular <request>
```

No arguments show available operations. An exact bare skill ID shows its details and installation or
loading choices; a non-command query searches IDs, names, descriptions and facets/tags. Search is
case-insensitive, returns selectable matches and never installs a guessed match. For example,
`architecture` must find `patterns-monolith-modular` through its declared facet. An unknown skill
returns a clear not-found message, such as "Sorry, we can't find that skill", with no mutation.
Search/discovery and install/load are distinct actions even when a short-form query is convenient.

Installation defaults to the catalog's advertised current release; `--latest` may express that
explicitly and `--version X.Y.Z` selects an exact available release. Resolve either choice to one
exact version/digest before preview and approval; never reinterpret latest during apply. Reject
conflicting version options or unavailable versions. Exact-version selection is not a persistent
hold: persistent pins and their effect on future upgrades are deferred.

Show the selected skill's required closure and explicitly offer optional additions. Require reviewed
approval before installation; searching or choosing a match alone is not write consent. The same
command loads installed canonical guidance and relevant resources without modifying files or silently
installing missing skills. Payload extensions remain independently versioned and registered with
Spec Kit, but the target adapter must stop generating per-skill public load commands. The library
entry point replaces that command proliferation; these adapter/verifier changes are follow-on work.

Pinned Spec Kit 1.2.3 already supports arguments in Copilot skills-mode and catalog search/current or
exact-version lookup. Its `specify extension update <id>` updates one extension; omitting the ID checks
all installed extensions and prompts before updating. These are inspected upstream capabilities, not
our implemented upgrade contract. Reuse compatible upstream primitives when future upgrades are
scoped, but first verify dependency constraints, local-edit protection and approval behavior. Do not
advertise or dispatch `upgrade-all` in this demo merely because the upstream command exists.

### Canonical Sources and Selection

Keep one canonical Copilot source and generate target layouts through scripts, not a second authored
tree. Broad-to-specific coordinated names are permitted only when folder/name alignment,
links/resources and native discovery remain valid. The owner approved 21 flat native skill renames,
implemented in reviewed batches. The modular-monolith native name becomes
`patterns-modular-monolith` while its distribution ID remains `patterns-monolith-modular`.
No retired native source shims are required; distribution migrations still need the catalog history
below. Preserve other source paths and links until an approved move occurs.
Distribution ID, source path, aligned native folder/frontmatter name and generated command name are
distinct. Keep the distribution ID stable across source/native renames by default. The initial metadata
uses the existing native skill names as distribution IDs; it creates no duplicate architecture guidance.
Current native layout and metadata discovery remain flat, with immediate-folder sidecars only.
Future directory deepening requires verified native-host discovery and supporting tooling changes;
this proposal does not claim nested folders work. A same-ID source/native-command rename needs no ID
migration, but still requires public-compatibility and version-impact assessment.
Upstream-generated `speckit-*` skill folders are owned and maintained by Spec Kit, not this library.
Exclude them from component metadata enrollment, normalization, independent versioning and release tags;
preserve their native runtime use without republishing them as library-owned components.

Define one format-neutral authoritative metadata contract for component identity, independent
version, optional facets and license/notice exceptions, required/optional dependencies,
external files and tooling prerequisites, with explicit repository license/notice defaults.
Derive invariant native entrypoints and source origin at packaging, not from author declarations.
The user selected one YAML sidecar per skill as the storage
strategy, replacing the earlier embedded JSON `## Skill Dependencies` proposal.
A central index may reference authoritative records but must not repeat dependency declarations.
The bounded metadata, local version-preparation, committed inventory-preview and deterministic local
archive slices, extension adaptation and bounded workspace installation are implemented; ordinary
Markdown links do not become graph edges. Publication remains deferred. Local inventory and archive
evidence are not immutable release records or rights approval.

### Metadata Contract

Use `.github/skills/<native-name>/skill.metadata.yaml` with the single authoritative
[draft 2020-12 JSON Schema](../.github/skills/skill-library/skill-metadata.schema.json) bundled in
the [skill-library skill](../.github/skills/skill-library/SKILL.md), with repository defaults in
[.config/skill-library.yaml](../.config/skill-library.yaml) validated by a separate
[closed defaults schema](../.github/skills/skill-library/repository-defaults.schema.json). Its
[valid synthetic template](../.github/skills/skill-library/examples/metadata.yaml.tmpl) is schema-only
example data, not a catalog record. Optional `$schema` paths are informational; the validator always
uses the bundled schema and never retrieves user-supplied references.
On 2026-10-27 the owner authorized this bounded implementation before Spec Kit initialization and
dogfooding, superseding the earlier sequencing only for this slice. That approval did not authorize
initialization; separately approved initialization and the authoring exercise subsequently completed
as recorded under [Handover](#handover).

| Declaration | Implemented authoring contract |
| --- | --- |
| Native identity | Derive the native name from the aligned folder and frontmatter; reuse native title/description rather than duplicating them. |
| `id`, `version` | The sidecar requires explicit component identity and exact plain `X.Y.Z` version, independent of repository GitVersion. Distribution ID may differ from native name. Initial `1.0.0` values are unpublished intent, not release evidence. |
| `facets` | Optional classification strings, independent of native identity and generated output format. |
| Repository `license`, `notices` | Declare known repository terms once: currently `license: MIT` and `notices: [LICENSE]`. License is required; notices are optional. These defaults neither infer nor relicense third-party content and do not establish redistribution rights. |
| Component `license`, `notices` | Optional genuine license override and additional root-relative notice paths. Component notices are additive to shared defaults, never replacements; inherited paths must not be repeated. A license override does not remove shared notices. |
| `required` | Component edges each contain `id` and exact `version`; every selected component brings its required transitive closure. |
| `optional` | Edges contain `id`, exact `version`, `selectionKey` and a succinct `reason` for the opt-in prompt. Preview includes their required closure only when explicitly selected. Archive builds reject optional selections and exclude optional-only payloads; the workspace installer selects separate required-only artifacts. |
| `externalFiles` | Explicit required external repository files contain `path`, `kind` (`instruction` or `notice`) and `loadingPurpose`. Internal skill-directory content is implicit; there is no `resources` field. |
| `tooling` | Entries contain `id`, `versionRequirement`, `scope` and `required`. Scope is `build`, `authoring` or `consumer`; version grammar is only exact `X.Y.Z` or `>=X.Y.Z`, not general semver ranges. Advisory prerequisites are not payloads and never trigger installation. |

Collection arrays (`facets`, `notices`, `required`, `optional`, `externalFiles`, `tooling`) are optional;
omission normalizes to empty, but explicit nulls and wrong types fail. Repository notice arrays follow
the same rule; empty component notices still retain inherited notices. Required component edges resolve
transitively; optional edges enter closure only through an
explicit reachable `component-id/selectionKey`. Selection never authorizes downloads or payload mutation.

External file and notice paths are repository-root-relative POSIX, not relative to the
sidecar or entrypoint. This permits shared files outside a skill, including
[C# instructions](../.github/instructions/dotnet.csharp.instructions.md). Only the informational
schema-relative `$schema` is an authored exception. Native entrypoint is always `SKILL.md` in the
discovered skill folder. Paths identify
payload inputs; `loadingPurpose` describes when to load them, not automatic instruction activation.

The three local sidecars demonstrate this contract:
[skill-library](../.github/skills/skill-library/skill.metadata.yaml),
[ports and adapters](../.github/skills/patterns-ports-and-adapters/skill.metadata.yaml) and
[modular monolith](../.github/skills/patterns-modular-monolith/skill.metadata.yaml).
Internal references/examples need no duplicate inventory. Shared C# and configuration instructions
are explicit external files. Ports and adapters offers one optional modular-monolith relationship for
module composition; other conditional specialization links are not blanket graph edges. These examples
do not establish a resource-complete distributable closure or a completed rights audit.

The [read-only validator](../.github/skills/skill-library/scripts/Invoke-Validation.ps1) uses the
[PyYAML reader](../.github/skills/skill-library/scripts/Read-Metadata.py) and bundled schema for closed
objects, types, enums and exact versions. It checks opted-in records, native alignment, declared paths,
duplicate IDs/edges, required/optional overlaps, exact dependency availability, required cycles and
cycles involving selected optional edges. It rejects ambiguous YAML, traversal, symbolic links including
path ancestors, case collisions in skill trees and conservative secret/cache filenames. It does not
claim a privacy scan, rights clearance or packaging inventory. Defaults and additional notices use
the same safe-path checks as external files, including regular-file kind and ancestor-link checks;
duplicate inherited/additional/external paths fail. No publication switch or unbound review flag exists.

PowerShell 7.4+, Python 3.11+ and the [pinned PyYAML prerequisite](../.github/skills/skill-library/scripts/requirements.txt)
are required for authoring validation. `-PythonPath` selects an existing interpreter; no prerequisite is
installed automatically. Tooling declarations are validated but never executed. Discovery skips
unconverted directories rather than requiring migration. Future packaging must include eligible
committed directory content, exclude ignored/untracked local files and validate its exact inventory,
transitive external prerequisites and output collisions. Packaging and installation must reuse the
authoritative graph, not create an independently maintained index of edges.

Sidecars hold edited declarations, not `entrypoint`, `origin`, `provenanceStatus`, generated hashes,
source commits, closure or resolved-version records. The entrypoint and source folder derive from
native discovery; packaging derives repository identity and revision from verified committed inputs.
Those facts belong in generated immutable provenance/release records; installed ownership, versions, hashes and recovery
state belong in the consumer inventory. Do not duplicate schema identity in a `schemaVersion` field.
The bounded installer uses repository-local `.specify/extensions` and Spec Kit's own registry, with
separate approval/operation evidence under `.specify/skill-library-install`. Profile installation is
deferred rather than an unresolved prerequisite for this implementation.

Evaluate [Agent Plugins 1.0.0](https://agent-plugins.org/specification) as an alternative or additional
generated output from that source. Its plugin manifest is not interchangeable with Spec Kit's
extension manifest; this evaluation promises neither implemented support nor a second packager.

### Exact Closure and Snapshots

The implemented [committed inventory preview](../.github/skills/skill-library/scripts/Invoke-InventoryPreview.ps1)
uses the existing validator's selected closure against one locally available commit. It includes
eligible committed internal content, mandatory external files and inherited/additional notices,
with every owner, inclusion reason and declaration source. Required dependencies are transitive;
optional relationships are excluded unless explicitly selected, then bring their required closure.
The [command contract](../specs/001-packaging-inventory-preview/contracts/inventory-preview.md)
separates the invoked trusted validation bundle from historical source data. Historical scripts,
filters, hooks and advisory tooling remain inert; committed ignore rules determine eligibility.
Success is emitted only after temporary inspection cleanup, and local edits are excluded.

This tooling remains owned by `skill-library`, not a second resolver under `.scripts/spec-kit/`.
Local archive building reuses its required-only inventory; workspace consumer selection also reuses
the authoritative graph contract and resolution rules. Resource prerequisites must not stop at an
instruction boundary. Deduplicate identical resolved nodes.
Missing selected content, cycles, version conflicts, traversal, symlink
escapes, duplicate output paths and case-insensitive collisions must fail with a useful graph path.
Local-link validation is a separate completeness check, not dependency inference.

The preview creates no archive or durable provenance record and does not establish redistribution
rights. Each future component version would have a generated reviewed immutable provenance/release record with
repository identity, exact source commit, derived skill folder/entrypoint, exact committed input paths
and SHA-256, resolved edges/versions, optional selections, inclusion reasons, tool/schema versions,
effective licenses and shared/additional notices, rights-review evidence bound to that inventory/revision,
matching component tag and artifact digest. The archive digest lives outside the archive. This is not
an authored sidecar or the consumer install inventory. Changed incorporated dependencies require a new
consumer version even when its own Markdown is unchanged. Reject changed bytes at an unchanged
version; historical rebuilds need the recorded inputs rather than today's working tree.

The ignored native baseline captured for the initial review is only a compatibility comparison artifact.
It inventories then-current working bytes, including the release-rule delta staged at that time.
It is neither a distribution snapshot nor runtime discovery evidence.

### Deterministic Local Archives

The [local archive entry point](../.github/skills/skill-library/scripts/Invoke-Archive.ps1) and
[isolated ZIP writer](../.github/skills/skill-library/scripts/Write-Archive.py) implement the
[skill-archive/1 contract](../specs/002-deterministic-skill-archives/contracts/archive-build.md).
Each invocation requires one explicit native root and packages its eligible committed required
closure, external instructions and applicable notices exactly once. Optional-only targets and their
dependencies are absent; independently required overlap remains included. Advisory optional declarations
may remain in source metadata. The existing optional inventory preview remains independently useful.

Output is a new directory containing `package.zip` and `package.zip.sha256`. The stored ZIP contains
generated `manifest.json` and source files under `payload/<repository-relative-path>`. Evidence binds
the source commit, component versions, file modes/digests, inclusion reasons and license/notice sources
to the captured trusted builder and exact runtime identities. The detached digest avoids self-hashing;
neither it nor the manifest establishes publisher authenticity, rights clearance or immutable release
history. Historical payload code remains inert and local edits do not replace committed bytes.

Linux CPython is the supported build platform. Exclusive output reservation, owned-entry rollback and
scratch/finalization acknowledgments protect the documented stable-parent/exclusive-use boundary.
Existing output is refused; ambiguous recovery material is retained and identified. Partial visibility
and crash remnants are possible, not an atomic-pair or hostile-writer guarantee. Native Windows and
other Python implementations are refused; cross-runtime byte equivalence remains unverified.

The [validation guide](../specs/002-deterministic-skill-archives/quickstart.md#convergence-follow-up)
records approved synthetic checks and an earlier separately approved real pilot/rebuild. These verify
local archive behavior, not a Spec Kit extension payload: this ZIP has no generated `extension.yml`,
registered command or installer. Extension adaptation, separate optional-skill downloads and consumer
installation require their own contracts and observed acceptance.

### PR-Based Component Releases

Local version preparation is implemented; CI integration is required for D3 and remains pending.
The planned flow separates reviewed version preparation from post-merge artifact publication:

1. The [skill-library workflow](../.github/skills/skill-library/SKILL.md#version-preparation) owns
  version preparation through its [local PowerShell writer](../.github/skills/skill-library/scripts/Invoke-VersionPreparation.ps1).
  Authors edit content and dependency
  intent normally, but should not hand-edit own release versions or required/optional version pins.
  Explicit initial versions remain deliberate bootstrap authoring, not automatic publication.
  Reuse the [release-train version-decision policy](../.github/skills/dotnet-release-train/SKILL.md#release-version-decision):
  major for breaking contracts, minor for compatible new functionality, patch for compatible fixes or
  internal refactoring. Verify numeric baseline versions against immutable release history and reviewed
  preparation state; require explicit decisions for breaking/substantial changes, never a blind patch
  default. That policy is not an existing reusable skill-bump script, and independent skill versions
  must not inherit repository GitVersion or its `+semver:` commit directives.
2. The writer detects affected components from skill-directory content, shared external
  inputs, repository defaults and incorporated dependency changes, not only direct Markdown edits.
  Propagate
  through both required and optional reverse dependency edges until a fixed point. A pin-only consumer
  change makes that consumer affected even when its Markdown is unchanged. Optional release propagation
  is independent of install-time optional selection, so unselected optional edges still propagate
  release changes. Required cycles and cycles involving selected optional edges still fail under the
  existing runtime closure rules; this release contract does not change them.
3. Compute a complete preview of baseline/target versions, reasons, paired own-version/exact-pin
  edits and matching immutable `<component-id>/X.Y.Z` tag names before writing. Require explicit apply
  approval with `-Apply -ReviewedFingerprint`, then recompute and write the consistent preparation for
  PR review. CI must detect affected skills and generate or validate this complete reviewed preparation,
  including a one-skill change, a multi-skill change and unchanged-input reruns; repository-level
  versioning is not a substitute. Unpublished IDs need explicit bootstrap acknowledgement and retain their authored initial
  version. Every affected released ID needs an explicit impact decision, including reverse consumers.
  For example, if a PR edits skills A
  and B and A depends on B, A's metadata must
  update both its own `version` and the required or optional exact `dependency.version` pin to B's new
  version. B's own version also changes. Bump each affected component at most once per preparation,
  even when it is both directly edited and reached through propagation. Preparation must be idempotent
  for unchanged inputs and existing prepared decisions, not repeatedly bump versions while traversing
  edges. Changed inputs/decisions require a refreshed preview. Do not create or push feature-branch tags.
4. After the PR merges and required checks pass, verify the merged default-branch commit and its
  reviewed metadata versions. Retain the top-level `version` for human-readable inspection and debugging;
  it declares release intent before publication. Separately authorized tooling creates immutable
  `<component-id>/X.Y.Z` tags identifying the released commit, not the pre-merge head. The release gate
  must reject any metadata/tag version mismatch, reused versions with changed inputs and conflicting
  existing tags.
5. Bind the generated exact-inventory provenance/release record, separate rights/privacy approvals
  and artifact digests to that same commit before publication. Verify matching immutable tags and
  preserve release/catalog history; a metadata validation pass is not publication approval.

The verified public Helm example supports version edits before PR review and tags targeting the merge
commit: [version preparation](https://github.com/f2calv/helm-charts/commit/6e020afd8113f7ffa45561808056d12d070e8432),
[PR 21](https://github.com/f2calv/helm-charts/pull/21) and
[workload/1.6.0 release](https://github.com/f2calv/helm-charts/releases/tag/workload/1.6.0).
Its [publisher at the merge commit](https://github.com/f2calv/helm-charts/blob/a6d10ce9cba7b66043fa7cbba080ec1d236352b5/.github/workflows/_publish-chart.yml)
reads chart versions and gates publication on the default branch. The inspected source establishes
no pre-PR detection/bump helper to reuse. The skill-owned writer is now implemented locally; release
scripts, tag creation and generated release records remain unimplemented. It verifies numeric local
tags against committed identity/version and ancestry, rejects incomplete/redirected history, and binds
preview approval to source inputs, decisions, implementation and Git state. It cannot prove that local
release refs are complete or historically immutable without separately trusted release evidence.
Parser-mark edits preserve unrelated YAML; complete staged validation precedes metadata-only writes.
Guarded rollback restores owned bytes on ordinary failures, preserves unexpected concurrent edits and
retains originals for manual recovery when necessary. Multi-file writes are not filesystem-atomic or
crash-durable; Windows behavior remains a native-host verification gate. The
[command contract and limits](../.github/skills/skill-library/SKILL.md#version-preparation) remain with
the owning skill rather than a second release policy here.

### Identity and Migration History

For an actual breaking distribution-ID change, propose one authoritative versioned migration history
in the library catalog, consumed from a trusted catalog snapshot. Do not hard-code separate installer
or extension alias lists, keep retired native source shims, or infer identity from folder names, Git
similarity or a major bump alone. Migration data is release history, not a source compatibility shim.
Preserve historical releases, immutable tags and catalog records; never reassign retired IDs to
unrelated content. Exact old-release installation must remain available when policy permits.

Each transition must identify the old ID and applicable exact historical versions, successor ID and
explicit version transition, reason/type (rename versus replacement), and compatibility/breaking action.
A stable-ID source-path change needs no ID migration, but release provenance and the installed inventory
must still support safe path replacement. Record explicit chains rather than guessing intermediate
identities. Migration-aware catalogs and replacement inventory remain deferred; the first-install-only
workspace tool does not implement these transitions. This contract adds no fields to authored sidecars
or an upstream catalog schema and does not block the bounded demo.

### Dependency-Aware Installation

The [workspace entry point](../.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1)
accepts one native root, explicit active optional keys, existing local catalogs/ZIPs and a compatible
initialized Copilot skills-mode consumer. It reuses the authoritative graph, freezes one source commit
and verifies a separate no-option required-only artifact for every selected extension. The root is
first, distinct optional target IDs follow in ordinal order, and the bound is sixteen extensions.
Overlapping resources remain complete independent copies; declining an offer opens no declined ZIP.

Preview is consumer-read-only. Apply recomputes the original inputs and requires the exact reviewed
fingerprint before reserving private evidence. A fresh isolated Python child passes the same verified
open archive stream to pinned Spec Kit 1.2.3 `ExtensionManager.install_from_archive`, with literal
expected identity/version, priority 10 and force false. There is no custom production extractor,
download, provisioning, core-command override or automatic installation hook.

Spec Kit owns payloads, generated loading commands and registration. The operation receipt is separate
approval/verification evidence, not another extension registry. Exact bytes, modes, notices, rendered
commands and registry/configuration additions are checked after each call. Revalidation between steps
protects earlier verified content and later absent targets. Existing same-version installations,
local edits, conflicting commands and unresolved operations refuse without adoption or replacement.

Stop on the first failure or cancellation, retain earlier Verified results and report Failed, Unknown
and Pending entries accurately. Preserve locks, receipts, scratch and partial paths for deliberate
manual reconciliation; do not retry an uncertain operation. Stable trusted inputs and exclusive use
are required. This is not a hostile-writer sandbox, atomic transaction or power-loss guarantee.

The per-extension loading commands are implemented pilot interfaces, not the selected demo interface.
The shared library command must expose this foundation through a packaged backend and add discovery,
version selection and installed-guidance routing. Its change to command generation/verification needs
focused regression and fresh consumer evidence. Upgrade selection, migration chains, major-version
approval and replacement/deletion policies remain outside this first-install foundation.

### Resource-Complete Generated Extensions

The implemented [extension adapter](../.github/skills/skill-library/scripts/Invoke-Extension.ps1)
currently generates a root `extension.yml`, a thin per-extension declared command,
the selected canonical sources beneath
`resources/library/<original-repository-relative-path>`, a dependency snapshot and applicable
license/notice material. Preserve source-relative layout and validate links within the selected
closure. Include required references, examples, assets, scripts and instructions, not only `SKILL.md`.
Do not execute included scripts merely to package them. For the selected demo, revise this adapter
and its exact verifier together so payload extensions do not each create a public command; the
bootstrap library extension owns the single public entry point and installed-resource routing.

The wrapper requests relevant resources on demand, not inline the library. Copied instructions
under `.specify/` do not acquire native `applyTo` activation. Original native files retain their
frontmatter and native route. Installation size, discovery metadata, loaded bodies and context
cost are different measures; selective-loading or token-saving claims require observed evidence.

The local archive contract above controls ordering, timestamps, encoding, serialization, modes and
compression/runtime policy. An extension-specific layout must establish and verify its own byte
contract rather than inherit loader compatibility from that ZIP. Keep the final digest outside its
archive. Future publication tooling would generate current and historical catalog records with exact
URLs/digests using the pinned
[version-selection contract](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/extensions/_catalog_versions.py).
Catalog history must not rewrite prior identities or digests. Curated bundles remain opt-in;
aggregate payload ownership must be agreed before aggregate publication.

### Provenance and Publication Boundary

The initial bounded review covered only the candidate skill, reference and example linked above. Local
history introduces all three in `2d20a36ae9e724c875f5c285f82a3d2e4bc7d0d3` on 2026-10-24,
with no later candidate-path commit observed at that initial review. Their text contains no file-specific SPDX license,
copyright notice or copied/adapted-origin declaration. The skill links official Microsoft
architecture guidance; the example explicitly calls itself synthetic and illustrative, not compiled.
Links and local Git authorship do not establish originality or third-party redistribution rights.

The root MIT choice and holder are settled, not a blanket clearance. Repository defaults record that
choice without overriding third-party terms. No distribution-specific provenance record for this
candidate was identified in the initial review. The later local manifest records source and declared
terms, not a rights-review decision. Before distributing
the positively selected closure, resolve each included source's origin/revision/path, applicable
license and required notices; retain notices and exclude unresolved content. Adjacent linked skills
were not audited or automatically selected. This review makes no legal compatibility determination.
Actual rights review remains a separate future gate tied to the exact selected committed inventory
and revision, not a boolean or review-status assertion in source metadata. Capture review evidence
and unresolved exclusions in the generated record; reject publication until those obligations are resolved.
If substantial upstream content is copied, assess its specific license and retain applicable notices;
the pinned [Spec Kit MIT license](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/LICENSE)
is evidence for that revision, not a substitute for reviewing selected material.

Local builds should need the documented metadata-validation runtime, Git and built-in ZIP/hash APIs,
not authentication.
Future publication needs separate rights, privacy, tag and release approvals. Verify an existing
approved remote tag, reject conflicting assets, preserve immutable history and review catalog
promotion separately. Component versions remain separate from repository GitVersion.

## Consequences

Native users avoid migration and maintainers retain one content authority. Exact snapshots improve
traceability but add resolver, packaging and provenance-maintenance costs. Generated copies are
disposable outputs, not another editable source. An omitted required resource must fail the build.

Installed payload replacement is not a universal merge of consumer edits. Preserve local changes
before exact upgrades and validate actual installer conflict/ignore behavior. A prior immutable
version can support deliberate recovery, but selecting it does not undo user data or local edits.
Archive digests verify bytes, not rights, publisher trust or model compliance.

## Validation and Delivery

Observed preparation is distinct from future acceptance:

* [x] Verify existing root MIT terms and notice without modifying them.
* [x] Review the candidate's three files and local history; record unresolved rights explicitly.
* [x] Record the approved component-tag policy, committed in `b22550b`, without creating tags.
* [x] Implement the authorized YAML sidecar contract, bundled authoritative schema, template,
  read-only validator and three example records before Spec Kit adoption. Simplify the records to
  explicit identity/version, inherited repository defaults and optional component exceptions; derive
  native source paths and remove the unbound publication declaration gate.
* [x] Run the initial 75 approved synthetic metadata/schema/defaults/dependency/path tests with Pester 5.7.1
  and PyYAML 6.0.3: 75 passed, zero failed or skipped. Run the existing native structural suite for
  the three opted-in skills: 12 passed, zero failed or skipped. Actual repository validation checks
  all three records and dependency-first optional closure. This is local authoring evidence, not
  packaging acceptance; editor YAML diagnostics may need a schema-cache refresh after contract edits.
* [x] Complete the approved seven-skill rename batch with static folder/name, resource and local-link
  checks and 28 previously approved automated structural checks. On 2026-10-27 the owner reported
  testing the skills successfully in another non-Dev-Container session; this is owner-reported native
  acceptance, not agent-observed discovery/invocation or packaged-route validation.
* [x] Settle bounded workspace targets, runtime-owned registration and separate recovery evidence;
  select the architecture root/optional pair for local demonstration. This is not redistribution clearance.
* [x] Verify generated custom loading command registration and owner-reported invocation in the completed
  extension pilot. Current installer-built peer invocation is recorded separately in feature 004.
* [ ] D4: package and install the single `skill-library` extension and observe native discovery of
  `/speckit-skill-library`; the current PowerShell installer is its foundation, not this deliverable.
* [ ] D5: implement shared discovery/install/load arguments, latest/default and exact-version selection,
  not-found behavior and optional consent; install multiple payload extensions without per-skill public
  commands and observe actual installed-only guidance reads through the shared entry point.
* [x] Demonstrate required transitive selection, explicit nested optional opt-in, shared ownership and
  notice provenance in a read-only committed inventory. The [validation guide](../specs/001-packaging-inventory-preview/quickstart.md#observed-checkpoints)
  records 163 passing focused tests (76 metadata, 38 preparation, 49 inventory), four passing owning-skill
  structural checks, deterministic pilot JSON and unchanged source/Git state. The pilot grows from
  one component/six files to two components/14 files when its optional relationship is selected.
* [x] Complete T039's configured scoped lint gate after explicit container-only provisioning approval:
  pre-commit 4.6.2 ran the root configuration on all 17 feature files; six applicable hooks passed,
  five skipped for unmatched file types, and no files were modified. Editor diagnostics and static
  parsing of all eight feature PowerShell files were clean; the updated records also passed lint.
* [x] Record the owner's 2026-10-27 decision to permanently skip inventory feature task T038.
  Python tooling stays in the dev container without Windows host provisioning. Native Windows
  behavior remains unverified; the waiver is not a test pass or support claim. The [feature tasks](../specs/001-packaging-inventory-preview/tasks.md)
  close with 39 completed tasks, one permanently skipped and none pending.
* [x] Demonstrate the workspace installer's resolved plan and approved real root/optional mutation;
  both exact-version extensions pass complete post-install verification.
* [x] Exercise negative resolver, integrity, local-edit, drift, conflict and interruption cases through
  synthetic contracts and real retained failure/child-loss consumers. No automatic recovery or
  hostile-writer/concurrent-install guarantee is claimed.
* [x] Implement the skill-owned preview/explicit-apply version writer; verify numeric baselines,
  impact decisions, paired own-version/required and optional pin propagation, shared inputs, converging
  dependency graphs and once-per-preparation idempotent reruns through focused synthetic fixtures.
  No real component metadata, tags or releases were mutated during implementation.
* [ ] D3: integrate affected-skill version preparation and exact versioned artifacts into CI; observe
  single/multi-skill changes, reverse-dependency edits, unaffected skills and idempotent reruns on actual
  workflow runs. Bootstrap versions alone and repository GitVersion do not satisfy this gate.
* [ ] D1-D2: show the consolidated/prefixed repository and metadata for every demonstrated skill as part
  of the final demo, rather than substituting earlier rename/schema checks for the presentation.
* [ ] Deferred: verify renamed-ID upgrades and same-ID source/native-path changes, exact historical-version
  scope, explicit chains, cycles/ambiguity, missing or unsupported targets, unapproved major rejection,
  already-installed destination collisions, dependent references and repeated-run idempotence.
  Demonstrate local-edit/shared-ownership/unselected-optional protection and interruption/rollback
  safety; retain policy-permitted exact historical installs. Migration-aware installation remains unimplemented.
* [x] Agree synthetic Pester coverage, focused stepwise execution and prerequisites through
  separate approvals; these do not authorize all future tests or setup.
* [x] Complete approved container build/runtime preparation using the
  [configuration](../.devcontainer/devcontainer.json),
  [lifecycle](../.devcontainer/Initialize-DevContainer.ps1) and
  [focused tests](../.github/skills/containers-devcontainer/scripts/tests/Initialize-DevContainer.Tests.ps1); see [Handover](#handover)
  for observed results and their environment boundary.
* [x] Adopt Spec Kit with separately approved initialization and conflict handling; adopt the
  [constitution](../.specify/memory/constitution.md) and complete a real authoring exercise through
  [the inventory feature](../specs/001-packaging-inventory-preview/spec.md), plan, tasks, analysis and
  implementation. This enhanced the existing `skill-library` skill and tooling, not a new unrelated
  skill. Standard Agent executed the Spec Kit workflow directly without HVE task-implementor orchestration.
* [x] Implement required-only deterministic local archives through
  [feature 002](../specs/002-deterministic-skill-archives/spec.md), with all
  [43 tasks](../specs/002-deterministic-skill-archives/tasks.md) completed. The approved Linux regression
  passed 245 tests: 84 metadata, 38 preparation, 49 inventory and 74 archive, with zero failures or
  skips. Independent header/member/digest checks, repeat bytes, fault/race cases, retained inventory
  scratch diagnostics, older commits, missing blobs and changed member bytes are recorded in the
  [validation guide](../specs/002-deterministic-skill-archives/quickstart.md#convergence-follow-up).
* [x] Complete the separately approved local pilot/rebuild with identical full ZIP bytes and detached
  digests, including committed notices and external instructions but no optional-only payload.
  The [pilot evidence](../specs/002-deterministic-skill-archives/quickstart.md#final-gates-and-pilot)
  binds its original source/builder tuple; later helper edits do not relabel those artifacts.
* [x] Verify the extension-specific layout through real runtime installation and the completed pilot's
  actual loading command; keep current peer editor acceptance distinct from historical evidence.
* [ ] Before demo artifact distribution: complete exact-inventory rights/privacy clearance and retain
  required notices for the chosen delivery. Signing and generalized public publication are deferred;
  local integrity checks do not grant publication approval.
* [ ] Deferred: demonstrate install/upgrade across published `1.0.0` and `1.1.0` releases, persistent
  pins and `upgrade-all`. Independent versioned demo packages do not establish upgrade support.

Container preparation and local ZIP checks alone do not demonstrate generated-extension runtime
compatibility. The completed extension pilot and current real installer record provide their own
bounded evidence; neither demonstrates releases, legal clearance, upgrades or context savings.
Local link/structure checks and editor diagnostics are not configured CI lint; the archive feature's
configured scoped lint and approved runtime evidence are recorded separately.

Shared CI delivery and the bootstrap library extension are required demo work. Broader automation
extraction, Bash/Python parity and a fresh-library scaffold remain deferred; no two-version upgrade
demonstration or additional dogfooding cycle is a prerequisite for implementing D1-D5.

## Handover

### Naming and Validation (2026-10-30)

The approved 21-skill native-name mapping is applied in domain batches under the
[library naming rationale](../.github/skills/skill-library/SKILL.md#skill-folder-naming).
The modular-monolith component retains ID `patterns-monolith-modular` and its existing dependency
pin despite the native name `patterns-modular-monolith`. Upstream `speckit-*` remains untouched;
first-party `spec-kit-guide` and `spec-kit-bootstrap` remain eligible for library enrollment.
Source/link validation is not editor-discovery or generated-extension acceptance.

Local validation exposed a pre-existing CI-contract mismatch in
[the coverage suite](../.scripts/tests/SkillValidationCoverage.Tests.ps1): the persistent .NET
example test incorrectly required its CI job to have no `if` key. The workflow intentionally skips
normal CI jobs only for manual skill-delivery preparation or builds. The test now checks that exact
predicate and an event/input matrix: pull requests and pushes always run the example job, normal
manual CI runs it, and manual `prepare`/`build` deliveries skip it. All 17 tests in the affected
coverage suite pass locally. The workflow and release fan-in remain unchanged; this is not evidence
of a complete repository regression or a new remote CI run.

### Current Progress (2026-10-29)

Feature 003 is complete for its local extension pilot, including real exact-version installation and
owner-confirmed native command invocation/installed-only guidance reads. Feature 004 implements the
workspace-only installer and has installed real `patterns-ports-and-adapters` and optional
`patterns-monolith-modular`, both `1.0.0`, from commit `71fab57257908a6b5b7a23057479c5f201699105`.
Both are Verified; the root ZIP is unchanged by optional selection and all sixteen canonical payload
files match their separate manifests. The two shared sources remain independent physical copies.

Real acceptance exposed and corrected three synthetic assumptions: stock initialization/manifest
handling, full source-manifest fields and Spec Kit's private `0700` extension-root mode. A failed real
consumer is retained, not repaired or reused. A later real child-loss case retains the Verified root,
Unknown peer and blocked retry after durable peer intent. Successful-run syscall tracing observes
extraction beneath private scratch, no runtime-child writes outside the consumer and no bytecode or
internet calls. Source and inspected Spec Kit profile state remain unchanged.

The [current validation record](../specs/004-bounded-workspace-installer/quickstart.md#real-runtime-demo)
owns artifact identities, final regression and the new consumer's editor acceptance. Its unperformed
gates remain explicit: the foundation ledger is 53/54 complete, with T053 pending. Preserve that
historical result when closing the current work for PR review; do not mark it passed or reuse it as
the future shared-command acceptance. The owner authorized preparing and merging the foundation PR
on 2026-10-29, conditional on required current-head checks; artifact publication is a separate gate.

Foundation integration/regression passed all 366 tests with no failures or skipped cases before
pre-PR review. Later rescue-state preservation, approval-size and aggregate-runner repairs passed
10 focused cases; that is not a full updated regression. The validation record distinguishes the
local baseline from current-head CI. Scoped offline lint, local links and editor diagnostics passed.
The next delivery is the shared
library command, bootstrap and CI skill versioning described by D1-D5, not completion of deferred
upgrade capabilities. Merge readiness for the current PR is independent of demo completion and must
also satisfy its actual remote checks and security/quality gates.

### Historical Archive Handover (2026-10-28)

The deterministic local archive feature is implemented in this checkout; this progress records local
implementation, not a published release. Feature 002 has completed specification, planning,
implementation and convergence follow-up;
all 43 saved tasks are checked. The final approved 245-test regression and scoped configured lint
passed. The subsequent read-only convergence assessment found no remaining feature-scope gaps and
left its task ledger unchanged. No new tests or archive builds were run for this progress update.

The local archive boundary is now implemented, not a proposed next increment. Native consumption and
optional inventory preview remain available. The retained real pilot belongs to its recorded original
builder tuple, while the later synthetic regression covers the cleanup/source-boundary follow-up.
Installation, extension adaptation, catalog/release publication, rights clearance and native Windows
verification remain outside this completed feature. No component versions, tags or releases were
created, and this progress does not accept the remaining ADR decisions.

Scope the next increment separately: settle the extension/loader contract, installation targets and
consumer inventory/recovery behavior before implementing the dependency-aware command. Optional related
skills must be offered as separate approved downloads/installations, not bundled into the chosen
skill's required-only archive. Publication and the two-version consumer demonstration remain later gates.

### Historical Implementation Handover (2026-10-27)

At that handover, the following work was recorded as committed locally, not pushed or released:

| Slice | Commit and evidence | Remaining boundary |
| --- | --- | --- |
| Metadata/defaults and local version preparation | `defb612`, `b352983`; [owning workflow](../.github/skills/skill-library/SKILL.md) | No published component versions or tags; native Windows verification remains open. |
| Spec Kit initialization | `d39c7f0`; generated native skills and `.specify/` scaffolding | Attached-editor discovery and packaged runtime behavior are not inferred from installed files. |
| Constitution adoption | `c91f5d2`; [constitution 1.0.0](../.specify/memory/constitution.md) | Maintainer approved removal of the temporary review report; this is not blanket ADR acceptance. |
| Committed inventory preview | `9c3cbaa`; [contract](../specs/001-packaging-inventory-preview/contracts/inventory-preview.md), [task state](../specs/001-packaging-inventory-preview/tasks.md) and [verification](../specs/001-packaging-inventory-preview/quickstart.md) | Closed: 39 tasks completed, T038 permanently skipped by owner decision; configured scoped lint passed. Native Windows remains unverified. No archive, install or publication support. |

The bounded inventory enhancement was specified, planned, tasked, analyzed and implemented using
Spec Kit, with synthetic fixtures for graph cases absent from the three real opted-in records.
The two accepted non-blocking analysis findings did not authorize broader planning changes.
The completed exercise is distinct from generated-extension consumption and fresh-library bootstrap.

The inventory feature closed with its recorded native Windows limitation. At this handover,
deterministic local archives were the proposed next increment, requiring a separate Spec Kit contract
and implementation approval. Their later completion is recorded in
[historical archive handover](#historical-archive-handover-2026-10-28); installation and publication were excluded at that checkpoint.
Keep one task authority for an active feature; no second HVE tracking plan was maintained for this
Spec Kit exercise.

The current checkout is the source of truth for branch and status. GitHub authentication was checked
and unavailable during the commit handover; no login, credential mount or push was attempted.
The requested local commits are one-shot operations: auto-commit and auto-push remain off. Further
tests, setup, publication and remote mutations require their applicable approvals.

### Historical Container Handover (2026-10-26)

Historical resume point, 2026-10-26: container preparation was verified; this ADR was Proposed.
Local commits `7bb1571a718117bc266e8bc87fcc6c249191df6b` (pinned development tooling) and
`2e85d2f596f820aade5572904e2375ca53c5540c` (native local-environment guidance) follow `b22550b`.
These commits have not been pushed. All three worktrees were clean before this ADR-only update;
query current branch and status rather than assuming a branch name. Auto-commit and auto-push are off.

The approved local build completed, two lifecycle reruns succeeded, and fresh recreation completed
automatic onCreate/postCreate hooks with exit code zero. The container ran non-root with UID 1000.
Specify `1.2.3` was verified from `git+https://github.com/github/spec-kit.git@v1.2.3`, resolving to
`5ea8b1cf0a38699340a38e00d02770308997d8c0`; version, help and installed provenance checks passed.
Observed supporting versions were uv `0.13.4`, Python `3.13.5`, PowerShell `7.6.9` and Pester `5.7.1`.
The 13 focused lifecycle tests passed with zero failures; effective source comparisons and sibling
read/write access passed. These results apply to the approved local configuration, not an unmodified
public-default build. Required local overrides remain outside the checkout; preserve them out of band.

The historical container recovery route used **Dev Containers: Attach to Running Container**,
not an unreviewed **Reopen in Container** that could bypass required out-of-band configuration.
Container recreation, extra mounts and credential transfer remain separately authorized operations.
Editor extension/customization discovery still needs observed evidence; host profile links and
settings do not automatically transfer. Ignored HVE tracking from earlier work is historical context,
not the active inventory feature's task authority.

Earlier update, 2026-10-27: rename commit `00bc81aa3316a41fc6ec9282644aee019f951fed` completed the
seven-skill batch. The owner reports successful native skill testing in another non-Dev-Container
session, not observed by the agent. This does not validate attached-container discovery or packaged
consumption. At that handover the metadata contract was design only and adoption-gated.
The later bounded authorization superseded that sequencing for metadata implementation only;
initialization and dogfooding were still pending at that earlier handover. Their subsequent completion
is recorded above. The status remains In Progress, not blanket ADR acceptance.

At the container handover GitHub authentication had not been checked and host credentials were not
mounted. Before future GitHub CLI operations, inspect authentication privately; do not expose its
output, log in or add credential mounts automatically. No standing commit or push approval exists.
At that historical point, packaging/installation tooling, exact-version demonstrations, provenance
clearance and publishing remained pending; handover was neither ADR acceptance nor rights approval.

## Open Questions and Reconsideration

* Choose the narrow artifact/catalog transport for D3-D5 and verify bootstrap backend/prerequisite
  availability in the consumer. Generalized public hosting is not required, but a maintainer-only
  temporary artifact path is not a reproducible installation experience.
* Select the CI trigger and explicit impact-decision input while retaining reviewed version edits,
  idempotence and post-merge immutable publication. The existing repository release workflow alone
  does not implement component releases.
* Reopen persistent pins, upgrades, migration, profile installs or broader publication only when
  separately scoped. None is a reason to block the agreed shared-command and CI demo work.
* Does a later pilot need a distinct newly authored skill in addition to the completed Spec Kit-authored
  inventory enhancement? The existing exercise validates local authoring, not a fresh-library scaffold
  or generated-extension consumption.
* What origin/notice evidence clears the first distributable closure? The local required-only pilot
  does not resolve rights approval or the separate download/install plan for optional related skills.
* In the validated pinned container, will the attached editor load the required extensions and
  discover shared customizations? Generated wrappers, native activation and consumer edit preservation
  still require observed session evidence; initialization alone does not establish them.

Reconsider the extension route if installed pinned-runtime evidence disproves payload completeness,
historical exact selection or native coexistence. Revisit extraction and aggregate bundles only
after demonstrated demand and a stable ownership contract.
