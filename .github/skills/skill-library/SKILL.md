---
name: skill-library
description: 'Author and validate skill metadata, preview committed inventories, apply approved workspace root/optional extensions, build deterministic required-only ZIPs and Spec Kit packages, prepare component versions and drive CI component artifacts. Use for metadata, packaging, version preparation, CI delivery or workspace installation. Linux Spec Kit 1.2.3 apply has real-runtime validation; editor invocation, CI-run evidence and publication retain separate gates.'
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
   Mark a tool optional only when the supported operation works without it; a different shell
   launcher does not eliminate the underlying runtime requirement. Declare each implemented scope.
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

The optional repository-root `.skillsignore` owns distribution exclusions. It accepts exact native
folder names or trailing `prefix-*` patterns, one per line; blank lines and whole-line `#` comments
are allowed. Paths, negation, other glob syntax and duplicate patterns fail. The repository excludes
`speckit-*` because those generated skills belong to upstream Spec Kit. Excluded folders remain
available to native VS Code discovery but never enter library metadata validation, inventory,
version preparation or structural skill checks, even if a sidecar appears. Explicit selection or
dependencies on excluded skills fail. Structural checks and the library share the same reader;
committed inventory reads the policy from its chosen revision, and preparation fingerprints it.
The first-party `spec-kit-guide` and `spec-kit-bootstrap` skills do not match `speckit-*` and remain
eligible for library metadata enrollment; describing Spec Kit does not make a skill upstream-owned.
Do not use this ownership policy to suppress unrelated lint or whitespace checks.

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
`resources/library/`, and adds a generated manifest and source/build evidence. Ordinary skill packages
declare their canonical `SKILL.md` as a passive template, not a public command. The adapter does not
resolve dependencies again, rewrite native guidance or include optional-only skills.

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
The extension declares `==1.2.3` compatibility and the `skill-extension/1` build contract. Its nonempty
`provides.templates` satisfies the pinned runtime without registering per-skill commands. Load through
the shared bootstrap below; select declared instructions by their manifest `external-instruction`
reason, not only a filename suffix. Copied instruction files do not acquire native `applyTo`
activation. No packaged scripts execute.

The [pilot validation guide](../../../specs/003-spec-kit-extension-pilot/quickstart.md) distinguishes
real catalog discovery, exact-version installation, digest/conflict refusal and installed-byte checks
from actual editor invocation. Manual resource reads or generated command files are not proof that
Copilot discovered/invoked the command in the consumer session. A discovered command may supply its
loader as an automatic Copilot attachment; do not require a separate tool read of that loader. Confirm
native command selection rather than manual file attachment, verify installed-only guidance reads,
and distinguish owner-reported runtime evidence from independently inspected traces.
Use Spec Kit's own installer for this
pilot; the workspace installer below adds bounded local optional selection and operation evidence.
Remote acquisition, upgrades and publication remain deferred. Local catalog integrity is not publisher
authentication or redistribution approval.

## Shared Library Bootstrap

For a `skill-library` source archive, supply `-LibraryCatalogPath` with one to 256 explicit
existing release catalogs and their sibling ZIPs. The adapter bundles those exact packages, a local
library index, dispatcher, approval worker, verifier, shared metadata schema/graph validator, strict
YAML reader, transitive helpers and both prerequisite lockfiles. No maintainer checkout or alternative
catalog is needed at runtime. Existing CPython 3.11+ with PyYAML 6.0.3 and Spec Kit 1.2.3 is required;
installation also requires PowerShell 7.4+ and Git. Never provision prerequisites silently.
The catalog bound is independent of the sixteen-root installation transaction bound. Keep old
published releases available; this bundled subset is not the permanent release archive.

The Monday demo keeps the existing Python/PowerShell implementation rather than parallel Python,
PowerShell and Bash engines. Native guidance can be read without executing its helpers, but the
bootstrap's current installer cannot run without its declared runtimes. Alternative engines are
deferred until after the demo: select real target environments, compare dependency and maintenance
costs, and require shared behavior and failure-contract coverage before claiming interchangeability.
Git remains an installation prerequisite in this guide; its minimum supported version has not yet
been established, so do not invent a numeric sidecar requirement merely to fill the schema.

The source/component ID and archive name remain `skill-library`. The generated bootstrap's runtime
extension ID is `skill`, its canonical command is `speckit.skill.library`, and native Copilot
skills-mode registration produces exactly `/speckit-skill-library`. The catalog key and generated
backend path use that runtime ID; build evidence and adapter results expose `RuntimeExtensionId`
separately from the source root. Spec Kit's extension listing therefore identifies the bootstrap as
`skill`. Do not add aliases to shorten the command: the pinned registrar creates extra public entries.

The [shared backend](./scripts/Invoke-Library.py) supports bundled discovery, details, installed-only
listing and verified installed guidance loading. `install <id>` defaults to the catalog-advertised
current release; `--latest` is explicit current selection and `--version X.Y.Z` selects exactly.
The result is a complete read-only Preview from the existing approval/evidence engine. Show its exact
versions, digests, consumer, required closure, optional choices, intended writes, blockers and
fingerprint. Only a ready preview is eligible for separate explicit approval. Apply with its exact
root `--version`, the same `--optional` keys, `--apply` and `--reviewed-fingerprint`; never reinterpret
latest during apply. Closed typed JSON connects the dispatcher to the worker without shell evaluation.

Native bootstrap registration, bundled discovery, source-independent approved two-extension
installation and installed-only guidance reads have real pinned-runtime validation. Both payloads
have empty command registrations. Actual editor invocation and CI component delivery remain separate
acceptance gates. Preserve failed consumers and use a fresh approved disposable consumer after a
bundle defect; never patch installed evidence in place.

## Read-Only Workspace Preview

Use the [workspace entry point](./scripts/Invoke-WorkspaceInstall.ps1) to inspect one committed native
root against existing local catalogs, prebuilt extension ZIPs and an initialized built-in Copilot
skills-mode consumer. This Linux-only MVP requires PowerShell 7.4+, Git and an existing CPython 3.11+
interpreter with PyYAML 6.0.3 and Spec Kit CLI 1.2.3. It never provisions prerequisites.

```powershell
$Preview = ./.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1 `
   -RepoRoot /workspace/source -SourceRevision HEAD -SkillName example-root `
   -WorkspacePath /workspace/consumer -CatalogPath /workspace/artifacts/catalog.json `
   -ArtifactDirectory /workspace/artifacts -PythonPath /workspace/tools/bin/python
$Preview | ConvertTo-Json -Depth 100
```

Source, consumer, catalog, artifact-directory and interpreter paths must be explicit, existing and
absolute. Committed source and consumer cannot contain one another. Linked paths/ancestors fail; a leaf
interpreter symlink is allowed and its resolved identity is bound. Supply stable trusted inputs and
exclusive workspace use. Dot-sourcing defines functions without running inspection or exiting the
host; `Invoke-SkillWorkspaceInstall` returns the same object. The script's `-Json` emits one JSON result.

The existing validator owns dependency closure and explicit optional-key validation. Preview
verifies each selected local `<id>-<version>.zip` against its unambiguous catalog record and required-only
committed inventory at the same frozen source commit, including
literal identity, notices, every resource byte/mode and the exact passive extension manifest.
Limits are 64 MiB per archive and uncompressed payload, 16 MiB per member and sixteen distinct extension
roots. Catalog URLs are provenance only. Declined optional ZIPs are never opened; offers default off,
and Markdown links do not create dependencies.

For standalone packaged inputs, use `-PackageIndexPath`, exact `-PackageVersion`, one artifact
directory and the same consumer/interpreter inputs instead of committed source inputs. Verified
sidecars pass the bundled schema and the same graph resolver, including offers from required
components and each required-only manifest. Independent releases retain their own source commits.
The only permitted source nested inside a consumer is the exact enabled, manifest-hash-registered
bootstrap library at `.specify/extensions/skill/library`, with its `catalog.json` and `packages`.
Other managed locations and modified bootstrap descriptors fail; this is not a general containment
exception. Catalog/tool hashes bind approval separately from ZIP evidence so apply retains the
same verified archive stream rather than opening it through generic tool hashing.

`Ready: true` includes bound source/tool/runtime/catalog/artifact identities, consumer path snapshots,
predicted payload/registry/configuration effects and a canonical lowercase SHA-256 fingerprint.
Registry prediction marks the runtime-generated installation timestamp rather than inventing a fixed
timestamp. Existing registry/configuration must round-trip without unrelated changes. External or
changed project adapters, hooks/events, unknown integration effects, collateral chmod, occupied targets
and unresolved operation evidence block readiness, including retained upstream rescue staging for a
selected extension. Canonical approval evidence is
limited to 4 MiB before reservation; saved receipts use the existing 64 MiB evidence-file read limit.
Missing/invalid inputs return `Ready: false`,
structured `Blockers` and a null fingerprint; inspect the safe code/scope, resolve the cause deliberately
and obtain a fresh preview. Exit codes are 0 for ready preview, 2 for blocked input and 4 for unexpected
inspection failure. Do not delete locks/receipts or adopt existing targets to make a preview ready.

Preview performs no consumer/profile writes, extraction, network access, manager construction or
payload execution. Temporary committed-input inspection remains owned by the existing inventory
helper. Preview `-ReviewedFingerprint` requests fail closed.
Readiness is not publisher authentication, rights clearance, installation approval or real-runtime/
editor acceptance. The [validation record](../../../specs/004-bounded-workspace-installer/quickstart.md)
separates synthetic root/optional checks from real-runtime and editor gates.

## Explicit Optional Selection

Pass exact active `component-id/selectionKey` values through `-OptionalSelection`; the authoritative
validator rejects duplicate supplied keys, unknown keys and keys declared by inactive components.
Selections are sorted for approval. Newly active components expose their own offers, but those offers
remain off unless explicitly selected too. No links, available artifacts or shared dependencies imply
consent. Multiple active declarations may select the same target: retain every reason and pin, but
install that target once. Duplicate dependency edges within a declaration remain invalid.

Use the explicit inputs in the next section, including the peer's existing catalog and artifact
directory. Add `OptionalSelection = @('example-root/related')` using a key actually offered by the
selected root. Review a new complete ready preview after changing any choice; root-only approval cannot
authorize a peer. Execution order is the original root followed by distinct selected optional targets
sorted by ID. Every extension uses its own no-option required closure. Committed-source selections
share a frozen commit; packaged releases retain their individual source commits;
choosing a peer never changes the root ZIP. Overlaps report source path/hash and owning extension IDs,
but complete resources and notices are copied separately beneath each extension-owned tree. There is
no physical deduplication, build, download or declined-artifact fallback.

## Approved Workspace Installation

Root and explicit optional first installation are implemented, synthetically exercised and verified
through the real pinned runtime in a disposable Linux consumer. Obtain approval for each maintained
consumer; demonstration success is not permission to mutate another workspace. Test approval never
authorizes a real install, artifact build or editor demo. The validation guide separates the new
consumer's editor acceptance from the earlier completed extension pilot.
Use the same explicit local inputs as preview; review the full ready result and obtain approval for
its exact fingerprint and consumer before invoking `-Apply`:

```powershell
$Installer = '/workspace/source/.github/skills/skill-library/scripts/Invoke-WorkspaceInstall.ps1'
$Inputs = @{
   RepoRoot = '/workspace/source'
   SourceRevision = 'HEAD'
   SkillName = 'example-root'
   WorkspacePath = '/workspace/consumer'
   CatalogPath = @('/workspace/artifacts/catalog.json')
   ArtifactDirectory = @('/workspace/artifacts')
   PythonPath = '/workspace/tools/bin/python'
}
$Preview = & $Installer @Inputs
$Preview | ConvertTo-Json -Depth 100
# Only after the separate approval and validation gates:
$Applied = & $Installer @Inputs -Apply -ReviewedFingerprint $Preview.Fingerprint
$Applied | ConvertTo-Json -Depth 100
```

Apply recomputes the complete preview from original arguments, never a caller-edited result object.
Missing, uppercase, stale or blocked approval refuses before reservation. Existing payload, command
or registered identity blocks even at the same version; there is no force, adoption, upgrade,
uninstall or resume route. Catalog URLs stay inert and packaged code stays inert.

Exclusive evidence lives beneath `.specify/skill-library-install`: `owner.json`, an operation `lock`,
and `operations/<fingerprint>/operation.json` with private `scratch/`. Directories use 0700 and evidence
files 0600. Prepared approval is flushed before revalidation; Attempting is flushed before delegation.
A fresh `-I -B` Python child receives only a child-local `TMPDIR` pointing at that scratch. It passes
the same regular single-link ZIP stream it hashed/inspected to Spec Kit 1.2.3's
`install_from_archive`, with priority 10, force false and exact expected ID/version. No compatibility
alias, custom production extractor, CLI refresh, scaffolding or profile/package configuration runs.

Verified requires literal identity/version, every canonical byte/mode/notice, no added public command,
expected registry/config additions and unchanged unrelated inspected state. For pinned Copilot
skills-mode payloads, `registered_commands` is an empty mapping and `registered_skills` is empty;
`manifest_hash` binds raw manifest bytes and only the runtime's UTC installation timestamp varies.
The runtime moves a private temporary directory into the extension root, preserving `0700`; ordinary
new payload subdirectories are `0755`. These modes are predicted and verified, not repaired afterward.
Warnings, skipped/missing registration, extra paths and incomplete checks suppress success. Raw
upstream diagnostics are discarded; structured failure categories do not echo their content.

Completed requires every selected extension Verified, a flushed final receipt and release of the unchanged owned lock.
The completed receipt and empty private scratch remain evidence, never authority to adopt a target.
Results separate completed, failed, unknown and pending entries, observed paths, recovery locations
and the last durable step. Exit 0 means verified completion, 2 means pre-reservation refusal, 3 means
a reserved failed/unknown operation, and 4 means unexpected failure.

Any post-reservation failure/cancellation stops work and retains the lock, receipt and partial/ambiguous runtime
paths; receipt-write failure cannot produce success. Do not delete locks or retry blindly. Preserve
old evidence outside the active operation namespace, inspect runtime registration and caller content,
then obtain separate approval for deliberate manual/runtime reconciliation. A fresh clean-target
preview is still required. There is no automatic rollback or recursive cleanup. Stable trusted inputs
and exclusive workspace use are required; this is neither a hostile-writer sandbox nor an atomic
filesystem transaction or power-loss durability guarantee. Synthetic scratch/stream observations do
not establish real upstream confinement or editor discovery/installed-only reads.

Failure observations retain readable payload, command, registry and evidence paths even if another
path cannot be inspected. An explicit unknown presence/error is not evidence that a write was absent;
inspection is bounded and does not follow linked partial files. A lost child or malformed response
triggers fresh read-only inspection, never a second install attempt. Reported KeyboardInterrupt marks
the operation Cancelled and its unverified extension Unknown; unreported child loss remains Unknown.
Unresolved-operation checks run before strict partial-tree parsing, so linked leftovers cannot hide
an abandoned operation behind an ordinary ownership conflict.

An entry remains Pending until its Attempting receipt flushes. Ordered selected steps revalidate before
each call and stop on the first failure, cancellation or evidence-write failure, retaining earlier
Verified entries and later Pending entries. Failure to persist Verified evidence does not erase a
completed verification; report the older last durable step as well. A foreign same-byte lock is never
released, even after a Completed receipt; that operation still returns Unknown and blocks retry.
These boundaries have synthetic cancellation, child SIGKILL, malformed-output and persistence-fault
coverage. A real root followed by a deliberately terminated peer child after durable intent also
preserves Verified/Unknown outcomes and blocks retry. Whole-orchestrator termination, machine crash/
power loss and interruption during actual upstream copying remain unverified. Between steps, earlier Verified bytes and the next absent targets must still match
the last durable observation. A failed, cancelled or uncertain peer never erases a verified root;
remaining entries stay Pending. Caller-edited plans cannot bypass full original-input recomputation.

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

## CI Component Delivery

The [delivery entry point](./scripts/Invoke-ComponentDelivery.ps1) reuses version preparation without
changing source, tags or releases. Default execution returns `skill-component-delivery/1` with the
complete preparation, `Ready`, `BuildReady`, source commit and fingerprint. Use the same explicit
`-ImpactJson` and `-BootstrapId` decisions as preparation. `BuildReady` requires complete decisions and
no outstanding metadata edits. Review and apply preparation separately, then commit it before building.

```powershell
./.github/skills/skill-library/scripts/Invoke-ComponentDelivery.ps1 `
   -ImpactJson '{"example-skill":"minor","example-consumer":"patch"}' `
   -PythonPath /path/to/python -Build -OutputDirectory /tmp/new-component-delivery
```

Build requires clean committed Linux source and a new output directory outside source/Git storage.
Only components with proposed tags are packaged, independently of repository GitVersion. Each has a
required-only native ZIP and `components/<id>/<version>/<id>-<version>.zip`, detached digest and catalog.
`delivery.json` records the preparation and exact artifact results; it is build evidence, not publication.
Source is rechecked through build completion. Failed builds retain partial output for inspection;
never adopt or overwrite it. Unchanged unrelated components receive no new package or version.

The bootstrap builds last and bundles newly built payload catalogs first. Supply explicit existing
`-LibraryCatalogPath` releases for unchanged skills or older exact dependency pins. Those existing
catalogs and sibling ZIPs pass the bootstrap adapter's ordinary digest checks and release-count bounds.

The reusable [delivery workflow](../../workflows/_skills-library-delivery.yml) offers `prepare` and `build`
modes with `impact-json` and JSON-array `bootstrap-ids`. It fetches full history, installs hash-locked
prerequisites and uploads `skill-components`, including the preparation report even when building fails.
An explicit `previous-delivery-run` can supply prior same-repository artifacts for unchanged releases;
it never selects a latest run implicitly. Its GitHub permissions are read-only; it creates no source
commit, tag, release or public catalog. Preparation edits still require separate review and commit.
Dispatch the registered [CI entry point](../../workflows/ci.yml) at the reviewed feature ref with
`skill-delivery=prepare` or `skill-delivery=build` to run only this job, without release tagging or
the normal CI suite. The default `off` retains normal CI, and dispatch controls cannot disable
pull-request or default-branch push checks. A new standalone workflow may not be dispatchable until
it exists on the default branch; the existing entry point avoids merging merely to test packaging.
Local synthetic checks cover single/multiple changes, both reverse edge types, unchanged components,
repeat artifact digests, CLI execution and exact bootstrap bundling. These are not evidence of an
actual Actions run. Request authorization before pushing or dispatching CI; editor invocation and
publication remain separate acceptance gates.

## Planned Release Flow

Version preparation and local archives above are implemented; PR creation and release publication remain
separate operations. Review preparation before opening a PR and rerun after changed inputs or decisions.
Follow the [published archive retention contract](../../../docs/adr-0001-copilot-spec-kit-distribution.md#published-archive-retention):
expiring CI artifacts are not permanent releases. Retain every published exact version and its evidence;
publication storage, immutable-release protections and independent backups remain separate setup gates.

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

### Skill Folder Naming

Prefer lowercase kebab-case `<domain>-<topic>` names in the flat skill directory. A domain prefix
groups related skills when browsing or completing names; the topic must still identify the actual
operation. Some additional length is justified, but avoid redundant category layers such as
`framework-dotnet-efcore` when `dotnet-efcore` conveys the same scope.

- Use one primary domain based on the implemented scope, not every technology mentioned. Keep
   `.NET`-specific guidance under `dotnet-*`; reserve `lang-csharp-*` for language-specific guidance
   rather than renaming the whole .NET ecosystem after its implementation language.
- Prefer specific domains such as `github-*`, `containers-*`, `terraform-*` and `gitops-*` over
   a broad `devops-*` bucket. Use `gitops-*` for actual reconciliation or Git-owned deployment
   workflows, not every Kubernetes-related skill.
- Use a scripting prefix such as `script-pwsh-*` when scripting itself is the subject. A bundled
   PowerShell helper does not make an otherwise domain-specific skill a scripting skill.
- Keep useful existing domain names rather than renaming for cosmetic uniformity. Use concise,
   recognizable terms; avoid arbitrary abbreviations and stacked prefixes. Express overlapping
   categories through metadata facets and discovery descriptions instead of longer folder names.
- Align the folder basename and native frontmatter `name`. Preserve an existing component `id`
   by default; changing a source name must not silently change release identity or published tags.
- Before bulk renaming, agree a complete current-to-proposed mapping with a reason for each entry,
   including unchanged names. Implement approved changes with `git mv` in small domain batches,
   starting with a low-coupling pilot; update references and review version impact in each batch.
   Run focused checks with test approval before separately authorized commits. Leave upstream-owned
   exclusions untouched and preserve the bootstrap's public command unless explicitly redesigned.

These principles guide naming review; individual remappings remain proposals until approved. A
folder rename alone is not evidence that native discovery or installed-path handling remains valid.

## Maintaining This Skill

- Recheck draft 2020-12 behavior when PowerShell's `Test-Json` or JsonSchema.Net changes.
- Recheck node/tag handling and scalar preservation when updating PyYAML or Python.
- Extend focused negative cases when dependency selection, filesystem link behavior or schema fields change.
- Keep `.skillsignore` semantics aligned across structural checks, committed inventory and preparation; exclude upstream metadata before parsing and bind policy changes into reviewed fingerprints.
- Exercise bootstrap catalog-capacity boundaries independently of installation transaction bounds and permanent release retention.
- Keep repository defaults, component overrides and additive notice checks aligned without treating declarations as rights clearance.
- Reconcile the implicit-directory contract with committed-file inventory and rights evidence before packaging.
- Recheck inert staging, isolated trusted imports, ordinal reasons, snapshot-only ignores and cleanup when Git, Python, PowerShell or filesystem behavior changes.
- Recheck raw ZIP headers, canonical evidence, runtime fingerprints and complete-byte rebuilds when CPython's zipfile/json behavior changes; ASCII names use flag 0 and UTF-8 names use 0x0800 without private encoders.
- Keep archive capture/fixtures aligned with the complete trusted bundle, including scripts/requirements.txt; builder identity is distinct from the committed payload's source. Exercise the extracted bootstrap backend using its default bundled paths so checkout-local transitive helpers cannot hide missing runtime files.
- Refresh scripts/requirements-spec-kit.txt with the complete exact-version SHA-256 wheel closure when changing CI's pinned runtime; retain the shared PyYAML lock separately. Check strict pip parsing/downloads for CI's Python version and wheel payload parity with the reviewed upstream source, not only the package name/version.
- Recheck Spec Kit manifest/catalog fields, three-part canonical command names, exact-version/digest selection and Copilot skills registration against the pinned installed runtime; aliases create extra public registrations. Consumer fixtures need integration manifests as well as init options.
- Recheck workspace preview API, integration-state schemas, registry/config serialization and chmod traversal against the pinned installed runtime. Even command-only extensions update the installed list and empty-hook configuration; predict those writes without constructing a manager.
- Exercise stock init-options, combined raw/parsed integration options, and both hash-tracked Copilot and core manifests, not only reduced fixtures; reject changed recorded files and unknown adapter effects. Match the archive producer's full GeneratedMembers/Limitations manifest shape, and retain the runtime's observed 0700 extension-root mode in predictions and fixtures.
- Refuse selected-extension rescue staging before delegation: upstream may restore or delete it even on a first install. Bound approval size before reservation and keep receipt reads consistent with evidence writes. Test focused runner aggregate failures and zero passing cases, not just individual FailedCount.
- Recheck the same-stream archive API and literal ID/version, Copilot's empty registered-command mapping, raw manifest hash and UTC timestamp when updating Spec Kit; preserve unrelated registration/configuration and bytes rather than accepting a successful return alone.
- Keep unresolved-operation checks ahead of strict partial-tree parsing and occupied-target checks on retries; distinguish synthetic child loss from whole-orchestrator loss, real-runtime confinement and editor acceptance.
- Exercise diagnostic capture with stdout/stderr output before raising a warning; warnings-as-errors make later probes unreachable. Keep reported cancellation distinct from an unverified extension outcome.
- Advance live Attempting state only after its receipt flushes; test Pending on failed intent, retained Verified on later persistence failure and foreign same-byte lock refusal after completion evidence.
- Preserve readable failure observations alongside explicit unknown records, including absolute ancestor snapshot paths. Assert present bytes/modes rather than a path-name match; reinspection after lost child output must not retry installation.
- Exercise ordered revalidation with earlier verified bytes and actual next-target drift, cancellation on both sides of intent and a pending remainder. PowerShell may wrap cancellation exceptions; retain token state as evidence.
- Keep source and packaged selection on the same schema and graph resolver, including required-component offers and selected mixed cycles. Bind each release's source commit and required-only inventory; test duplicate target reasons across active declarations, not invalid duplicate edges within one declaration.
- Recheck passive template validation and empty payload command registrations against the real runtime. Keep ZIP evidence separate from generic tool hashes so approval revalidation preserves single-open, same-stream installation.
- Recheck execution Position, indexed registry/config predictions and receipt outcomes together when changing multi-extension evidence; artifact records already carry Position. Preserve complete overlap copies and self-test selected/declined/nested ZIP tripwires.
- Allow hardlinked read-only installed prerequisites when capturing runtime identity; retain single-link ownership checks for managed consumer/evidence files. Keep byte/RECORD hashes and symlink checks in both cases.
- Keep extension-adapter binary stream and dot-source parameter regressions: preserve byte arrays as single return objects and explicitly retain caller destinations, catalog inputs and CLI defaults when loading parameterized scripts.
- Recheck descriptor-relative exclusive reservation, immediate ownership records, fault/race cases and scratch/finalization acknowledgments when changing Linux filesystem or process behavior; cleanup failures must never produce success.
- Keep prohibited-operation tripwires self-validating and arm them after synthetic fixture setup; historical payload code stays inert, and JSON evidence comparisons must ignore object-key order while preserving array order.
- Recheck local-tag evidence, baseline decisions, fixed-point propagation and idempotence when changing preparation.
- Keep CI delivery on the same preparation and archive/adapter paths. Exercise prepared committed builds, true dirty-source refusal, independently named artifacts, unchanged components, repeat digests and bootstrap-last catalog ordering; a workflow parse or synthetic run is not actual CI evidence.
- Keep limited delivery dispatch separate from normal CI/release gates. Reusable delivery concurrency must have its own suffix because the caller's `github.workflow` value is inherited; matching keys can cancel the caller.
- Keep synthetic self-preparation coverage and its complete helper bundle: the component containing the writer is also an input, so post-write implementation binding must allow exactly its reviewed metadata scalar edits. Freeze the trusted library tree during fingerprint tests; concurrent edits intentionally invalidate their source snapshots.
- Recheck scalar marks, input binding, cooperating-writer handles and guarded rollback on Python, Git, PowerShell or filesystem changes; local tags are not proof of remote completeness or historical immutability.
- Verify native discovery before deepening folders; keep catalog migration history and installer recovery aligned.
