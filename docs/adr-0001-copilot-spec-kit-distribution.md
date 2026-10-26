# ADR 0001: Local-First Copilot and Spec Kit Distribution

**Status:** Proposed.
**Date:** 2026-10-26.
**Scope:** Optional distribution of selected native customizations as independently versioned Spec Kit extensions.

## Context and Problem

The [native library contract](../.github/copilot-instructions.md#setup) supports workspace and
profile-linked consumption of the canonical instruction and skill folders. Selective, versioned
distribution must not require existing consumers to migrate or maintain a second Markdown source.
Library maintainers and selective consumers are the proposed pilot audiences, not validated customers.

Local source inspection at commit `a161439e9696211c34c5a468a7811f8944c111da` establishes:

* The root [MIT license](../LICENSE) and its holder notice already exist. Retain them unchanged;
  the copyright and permission notice must accompany copies or substantial portions.
* [Ports and adapters](../.github/skills/ports-and-adapters/SKILL.md), its
  [boundary reference](../.github/skills/ports-and-adapters/references/boundary-contracts.md) and
  [provider example](../.github/skills/ports-and-adapters/examples/provider-substitution.md)
  supply resource-bearing native architecture guidance. Ordinary links are not dependency declarations.
* No local `.specify/`, `specs/`, `.config/spec-kit/` or `.scripts/spec-kit/` exists at inspection.
  Existing native guidance is not evidence of Spec Kit adoption, dogfooding or packaged consumption.
* The approved [release rule](../.github/instructions/github.instructions.md#releases) is a staged
  working-tree change beyond that commit: independently versioned non-Action monorepo components
  may use immutable `<component-id>/X.Y.Z` tags, without `v` prefixes or floating aliases.
  This policy approval authorizes no tag creation, push or release.

Prior source research targets Spec Kit `1.2.3` at
`5ea8b1cf0a38699340a38e00d02770308997d8c0`. Its
[extension implementation](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/extensions/__init__.py)
supports manifest-bearing payload trees, while the
[preset manifest](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/presets/_manifest.py)
does not establish an arbitrary `provides.files` installer. These are pinned source findings from
prior research, not fresh runtime acceptance or a claim about later releases.

## Goals and Constraints

* Preserve native paths, names, frontmatter, `applyTo`, workspace/profile use and existing invocation.
* Author Markdown once; generate wrappers and payload copies only as build outputs.
* Select components and optional dependencies explicitly, with complete required resource closure.
* Version each component independently, recording exact inputs, dependency snapshots and SHA-256.
* Start with local PowerShell tooling and GitHub Release assets, without an Actions prerequisite.
* Keep setup, tests, initialization, commits, pushes, tags and publication behind separate approvals.

Whole-library migration, global instruction injection, automatic rights clearance and immediate
automation extraction are non-goals. No Spec Kit setup or execution is authorized by this proposal.

## Options Considered

| Option | Benefits | Costs and risks | Assessment |
| --- | --- | --- | --- |
| Keep native consumption only | No new tooling or migration | No exact component snapshots or release demo | Retain as a fully supported route, but insufficient alone |
| Maintain a second categorized source tree | Simple packaging layout | Duplicated guidance and broken native paths | Reject |
| Use upstream presets as arbitrary file installers | Appears to reuse a package mechanism | Pinned contract does not establish that behavior | Reject for resource-bearing capabilities |
| Generate extensions from explicit local closure | One source, selective artifacts, auditable inputs | Requires resolver, snapshot and runtime validation | Recommend |
| Require hosted workflows or OCI first | Central automation and transport | Setup and release-train cost before proving the contract | Defer |

## Proposed Decision

### Canonical Sources and Selection

Keep existing native sources unchanged. Optionally map the proposed distribution ID
`architecture-hexagonal` to the existing `ports-and-adapters` skill; do not create duplicate native
architecture guidance. Package identity, native skill name and generated command name are distinct.
The ID remains proposed, not an installable product.

Proposed metadata under `.config/spec-kit/` would own component identity, independent version,
source entrypoint, facets and origin/license records. A structured JSON contract under
`## Skill Dependencies` in selected canonical Markdown would own required/optional dependencies,
typed resources and tooling prerequisites. Metadata must not maintain a second dependency graph.
No such contract or schema is implemented yet; ordinary Markdown links do not become graph edges.

### Exact Closure and Snapshots

Proposed tooling under `.scripts/spec-kit/` would resolve exact versions for the pilot, starting
from selected roots. Required skill, instruction and resource dependencies are transitive;
optional nodes are excluded unless explicitly selected. Resource prerequisites must not stop at
an instruction boundary. Missing selected content, cycles, version conflicts, traversal, symlink
escapes, duplicate output paths and case-insensitive collisions must fail with a useful graph path.
Local-link validation is a separate completeness check, not dependency inference.

Each component version would have a reviewed immutable snapshot recording source commit,
input paths and SHA-256, resolved edges/versions, optional selections, inclusion reasons,
tool/schema versions and license provenance. Changed incorporated dependencies require a new
consumer version even when its own Markdown is unchanged. Reject changed bytes at an unchanged
version; historical rebuilds need the recorded inputs rather than today's working tree.

The ignored native baseline captured for this review is only a compatibility comparison artifact.
It inventories current working bytes, including the approved staged release-rule delta from HEAD.
It is neither a distribution snapshot nor runtime discovery evidence.

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

The bounded review covers only the candidate skill, reference and example linked above. Local
history introduces all three in `2d20a36ae9e724c875f5c285f82a3d2e4bc7d0d3` on 2026-10-24,
with no later candidate-path commit observed. Their text contains no file-specific SPDX license,
copyright notice or copied/adapted-origin declaration. The skill links official Microsoft
architecture guidance; the example explicitly calls itself synthetic and illustrative, not compiled.
Links and local Git authorship do not establish originality or third-party redistribution rights.

The root MIT choice and holder are settled, not a blanket clearance. No distribution-specific
provenance record for this candidate was identified in the inspected material. Before distributing
the positively selected closure, resolve each included source's origin/revision/path, applicable
license and required notices; retain notices and exclude unresolved content. Adjacent linked skills
were not audited or automatically selected. This review makes no legal compatibility determination.
If substantial upstream content is copied, assess its specific license and retain applicable notices;
the pinned [Spec Kit MIT license](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/LICENSE)
is evidence for that revision, not a substitute for reviewing selected material.

Local builds should need PowerShell, Git and built-in JSON/ZIP/hash APIs, not authentication.
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
* [x] Record the approved staged component-tag policy without creating tags.
* [ ] Approve this Proposed ADR and settle the pilot selection and authoring exercise.
* [ ] Agree coverage/execution policy and prerequisites before running tests or setup.
* [ ] Adopt Spec Kit here with approved conflict handling; demonstrate real skill authoring before
  fresh-library bootstrap. Existing native guidance alone does not satisfy dogfooding.
* [ ] Verify graph failures, exact snapshots, resource-complete inventories, license gates and
  equal byte hashes from two builds of the same recorded inputs.
* [ ] Demonstrate authorized published `1.0.0` and `1.1.0` exact install/upgrade/history, native
  compatibility and observed resource loading in representative Copilot sessions.

No runtime compatibility, deterministic archive, release, legal clearance or context saving has
been demonstrated by writing this ADR or hashing native files. Local link/structure checks and
editor diagnostics are not configured CI lint. Build is not applicable to this documentation slice.

Later shared automation, Bash/Python parity, glossary/crosswalk/demo material and a minimal
fresh-library scaffold remain separate planned work. Extract automation after the local contract
and two-version demonstration work; bootstrap a fresh library only after here-adoption and dogfood.

## Open Questions and Reconsideration

* Does a meaningful Spec Kit-authored enhancement of `ports-and-adapters` satisfy the requested
  creation exercise, or is a distinct bounded skill required? Explicit agreement is outstanding.
* Which optional nodes and resources constitute the first positively selected pilot closure,
  and what origin/notice evidence resolves its third-party rights?
* Which approved environment, pinned runtime and execution policy will validate generated wrappers,
  native activation and consumer edit preservation?

Reconsider the extension route if installed pinned-runtime evidence disproves payload completeness,
historical exact selection or native coexistence. Revisit extraction and aggregate bundles only
after demonstrated demand and a stable ownership contract.
