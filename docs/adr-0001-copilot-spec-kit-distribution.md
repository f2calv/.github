# ADR 0001: Local-First Copilot and Spec Kit Distribution

**Status:** In Progress. Metadata, local version preparation, committed inventory preview and Spec Kit adoption are implemented locally; remaining distribution decisions are proposed.
**Date:** 2026-10-26.
**Last Updated:** 2026-10-27.
**Scope:** Optional distribution of selected native customizations as independently versioned Spec Kit extensions with dependency-aware installation.

## Context and Problem

The [native library contract](../.github/copilot-instructions.md#setup) supports workspace and
profile-linked consumption of the canonical instruction and skill folders. Selective, versioned
distribution must not require existing consumers to migrate or maintain a second Markdown source.
Library maintainers and selective consumers are the proposed pilot audiences, not validated customers.

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
* Select components and optional dependencies explicitly, with complete required resource closure.
* Version each component independently, recording exact inputs, dependency snapshots and SHA-256.
* Start with local PowerShell tooling and GitHub Release assets, without an Actions prerequisite.
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
| Add a dependency-aware extension command | Consumer selection reuses the packaging graph | Requires approval, ownership and recovery safeguards | User-chosen direction; runtime acceptance pending |
| Generate Agent Plugins from the same source | Alternative or additional client packaging | Different manifest and discovery contract | Evaluate; no second packager implemented |
| Require hosted workflows or OCI first | Central automation and transport | Setup and release-train cost before proving the contract | Defer |

## Proposed Decision

### Canonical Sources and Selection

Keep one canonical Copilot source and generate target layouts through scripts, not a second authored
tree. Broad-to-specific coordinated names are permitted only when folder/name alignment,
links/resources and native discovery remain valid. The owner approved a first batch of seven flat
native skill renames, including `patterns-monolith-modular`; further taxonomy proposals remain
unapproved. No retired native source shims are required; distribution migrations still need the
catalog history below. Preserve other source paths and links until an approved move occurs.
Distribution ID, source path, aligned native folder/frontmatter name and generated command name are
distinct. Keep the distribution ID stable across source/native renames by default. The initial metadata
uses the existing native skill names as distribution IDs; it creates no duplicate architecture guidance.
Current native layout and metadata discovery remain flat, with immediate-folder sidecars only.
Future directory deepening requires verified native-host discovery and supporting tooling changes;
this proposal does not claim nested folders work. A same-ID source/native-command rename needs no ID
migration, but still requires public-compatibility and version-impact assessment.

Define one format-neutral authoritative metadata contract for component identity, independent
version, optional facets and license/notice exceptions, required/optional dependencies,
external files and tooling prerequisites, with explicit repository license/notice defaults.
Derive invariant native entrypoints and source origin at packaging, not from author declarations.
The user selected one YAML sidecar per skill as the storage
strategy, replacing the earlier embedded JSON `## Skill Dependencies` proposal.
A central index may reference authoritative records but must not repeat dependency declarations.
The bounded metadata, local version-preparation and committed inventory-preview slices are implemented;
ordinary Markdown links do not become graph edges. Archive creation, installation and publication
remain unimplemented. Local inventory output is review evidence, not an immutable release record.

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
| `optional` | Edges contain `id`, exact `version`, `selectionKey` and a succinct `reason` for the opt-in prompt. Exclude unless explicitly selected, then include their required closure. |
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
[modular monolith](../.github/skills/patterns-monolith-modular/skill.metadata.yaml).
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
Repository-local versus user-profile installation and inventory placement remain open decisions that
block installer implementation, not this metadata design.

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
Future packaging and consumer selection must reuse its authoritative graph contract and resolution
rules. Resource prerequisites must not stop at an instruction boundary. Deduplicate identical resolved nodes.
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

### PR-Based Component Releases

Local version preparation is implemented; the planned PR/publication flow publishes only after merge:

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
  PR review. Unpublished IDs need explicit bootstrap acknowledgement and retain their authored initial
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
identities. Catalog serialization, storage paths and the installed-inventory schema remain undecided;
this contract adds no fields to authored sidecars or an upstream catalog schema.

### Dependency-Aware Installation

The user has chosen a namespaced custom command as the installation direction, not accepted its
runtime implementation or this ADR. A custom Spec Kit extension would declare an agent/chat command
that invokes a deterministic packaged PowerShell installer. Proposed example:
`/speckit-library-install containers-docker-compose`; the final rendered name depends on actual registration.
This is not a new terminal `specify` subcommand, a core-command override or an automatic install hook.
Pinned Spec Kit `1.2.3` source provides integration evidence through
[`register_commands_for_agent` and the manifest validator for `provides.scripts`](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/extensions/__init__.py)
and [agent registration layouts](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/agents.py),
not proof that this proposed command is registered or runs successfully.

Read and validate metadata and the trusted catalog snapshot before payload mutation. For upgrades,
resolve migration history from the installed exact identity/version before selecting the latest
allowed release; never cross an unapproved major. Reject ambiguous transitions, missing targets,
cycles and any installed version with no supported transition. Resolve selected roots, migrated
dependent references and required transitive dependencies into an exact-version, integrity-checked
plan using the shared graph contract above. Automatic resolution is not automatic approval.
Related optional skills require
explicit opt-in; `containers-devcontainer` is illustrative, not an asserted dependency of
`containers-docker-compose`.
Preview deprecation and proposed replacement, complete roots/dependency/optional selections, version
transitions, managed target paths, proposed deletions and conflicts, including an already-installed
destination. Require explicit approval, especially for major changes, then stage and validate verified
replacement payloads before writing installation targets.

The proposed install inventory records exact distribution ID/version, installed native names, managed
paths/hashes, ownership and source catalog provenance. Preserve local edits, shared ownership and
unselected optionals. Retire only verified unchanged, owned old files after replacement staging and
validation; shared files must not be deleted while another owner needs them. Reject concurrent mutation
and recheck target state before writes. Failed or interrupted installs must retain a recoverable
inventory for deliberate recovery/rollback without discarding local edits; staging does not imply
atomic multi-file installation. Installation targets, inventory location/schema and concrete recovery
mechanics remain design decisions and acceptance work, not guarantees of an existing installer.

### Resource-Complete Generated Extensions

Generate a root `extension.yml`, a thin declared command, the selected canonical sources beneath
`resources/library/<original-repository-relative-path>`, a dependency snapshot and applicable
license/notice material. Preserve source-relative layout and validate links within the selected
closure. Include required references, examples, assets, scripts and instructions, not only `SKILL.md`.
Do not execute included scripts merely to package them.

The wrapper would request relevant resources on demand, not inline the library. Copied instructions
under `.specify/` do not acquire native `applyTo` activation. Original native files retain their
frontmatter and native route. Installation size, discovery metadata, loaded bodies and context
cost are different measures; selective-loading or token-saving claims require observed evidence.

Define deterministic archive ordering, timestamps, text encoding, serialization, file modes and
compression/runtime policy; sorted inputs alone do not prove deterministic bytes. Record the archive
digest outside the archive to avoid recursive hashing. Generate current and historical catalog
records with exact URLs/digests using the pinned
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
candidate was identified in the inspected material. Before distributing
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
* [ ] Settle installation targets, inventory/recovery contract and the first distributable pilot
  closure; accept the remaining distribution decisions separately from bounded implementation progress.
* [ ] Verify actual custom command registration and rendered name in the pinned Copilot integration,
  invoking the packaged installer without overriding core commands or using automatic install hooks.
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
* [ ] Demonstrate the packaged installer's resolved plan and separately approved payload mutation;
  a successful read-only inventory does not establish installation behavior.
* [ ] Verify negative resolver cases, including cycles, version/integrity and path conflicts, plus
  install inventory, concurrent mutation rejection and interrupted-install/local-edit recovery.
* [x] Implement the skill-owned preview/explicit-apply version writer; verify numeric baselines,
  impact decisions, paired own-version/required and optional pin propagation, shared inputs, converging
  dependency graphs and once-per-preparation idempotent reruns through focused synthetic fixtures.
  No real component metadata, tags or releases were mutated during implementation.
* [ ] Verify future renamed-ID upgrades and same-ID source/native-path changes, exact historical-version
  scope, explicit chains, cycles/ambiguity, missing or unsupported targets, unapproved major rejection,
  already-installed destination collisions, dependent references and repeated-run idempotence.
  Demonstrate local-edit/shared-ownership/unselected-optional protection and interruption/rollback
  safety; retain policy-permitted exact historical installs. Migration-aware installation remains unimplemented.
* [x] Agree synthetic Pester coverage, focused stepwise execution and prerequisites through
  separate approvals; these do not authorize all future tests or setup.
* [x] Complete approved container build/runtime preparation using the
  [configuration](../.devcontainer/devcontainer.json),
  [lifecycle](../.devcontainer/Initialize-DevContainer.ps1) and
  [focused tests](../.scripts/tests/Initialize-DevContainer.Tests.ps1); see [Handover](#handover)
  for observed results and their environment boundary.
* [x] Adopt Spec Kit with separately approved initialization and conflict handling; adopt the
  [constitution](../.specify/memory/constitution.md) and complete a real authoring exercise through
  [the inventory feature](../specs/001-packaging-inventory-preview/spec.md), plan, tasks, analysis and
  implementation. This enhanced the existing `skill-library` skill and tooling, not a new unrelated
  skill. Standard Agent executed the Spec Kit workflow directly without HVE task-implementor orchestration.
* [ ] Verify deterministic resource-complete archive builds, inventory-bound rights/privacy gates
  and equal byte hashes from two builds of the same recorded inputs. Deterministic preview JSON
  does not prove deterministic archive bytes or legal clearance.
* [ ] Demonstrate authorized published `1.0.0` and `1.1.0` exact install/upgrade/history, native
  compatibility and observed resource loading in representative Copilot sessions.

Container preparation and the inventory authoring exercise do not demonstrate generated-extension runtime compatibility, deterministic
archives, releases, legal clearance or context savings. Local link/structure checks and
editor diagnostics are not configured CI lint. No archive packaging build has run.

Later shared automation, Bash/Python parity, glossary/crosswalk/demo material and a minimal
fresh-library scaffold remain separate planned work. Extract automation after the local contract
and two-version demonstration work; bootstrap a fresh library only after here-adoption and dogfood.

## Handover

### Current Progress (2026-10-27)

The following work is committed locally, not pushed or released:

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

The inventory feature is closed with its recorded native Windows limitation. Scope the next
distribution slice separately rather than interpreting the remaining ADR checklist as implementation
authorization. A proposed next increment is deterministic local archive creation from recorded
committed inputs; define its format, build contract and provenance/rights boundaries through Spec Kit
before implementation. Installation and publication remain excluded. Keep one task authority for an
active feature; no second HVE tracking plan was maintained for this Spec Kit exercise.

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
Packaging/installation tooling, exact-version demonstrations, provenance clearance and publishing
remain pending; handover is neither ADR acceptance nor rights approval.

## Open Questions and Reconsideration

* Should installed payloads be repository-local or user-profile, where will the ownership inventory
  live, and what recovery contract will the revised plan validate?
  Which further naming changes and generated output formats should the pilot use?
* Does a later pilot need a distinct newly authored skill in addition to the completed Spec Kit-authored
  inventory enhancement? The existing exercise validates local authoring, not a fresh-library scaffold
  or generated-extension consumption.
* Which optional nodes and resources constitute the first positively selected pilot closure,
  and what origin/notice evidence resolves its third-party rights?
* In the validated pinned container, will the attached editor load the required extensions and
  discover shared customizations? Generated wrappers, native activation and consumer edit preservation
  still require observed session evidence; initialization alone does not establish them.

Reconsider the extension route if installed pinned-runtime evidence disproves payload completeness,
historical exact selection or native coexistence. Revisit extraction and aggregate bundles only
after demonstrated demand and a stable ownership contract.
