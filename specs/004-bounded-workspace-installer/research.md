# Research: Bounded Workspace Installer

**Date**: 2026-10-28. Planning evidence only; no tests, builds, downloads or installs executed.

## Evidence And Unknowns

Two read-only research tasks inspected the existing committed inventory boundary and the installed
Spec Kit CLI 1.2.3 implementation. Local source inspection also verified the archive installer
signature, its compatibility wrapper and the CLI's separate event/configuration steps. The following
decisions resolve the technical choices; executable acceptance remains pending.

The preceding [pilot research](../003-spec-kit-extension-pilot/research.md) records the pinned upstream
revision. Relevant public sources are the [extension manager](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/extensions/__init__.py),
[add command](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/extensions/command_add.py)
and [integration installer](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/integrations/installer.py).
Installed source was the immediate evidence, not an assumption that an external branch remains
unchanged. Implementation must capture the installed distribution version and participating module
hashes in preview/approval evidence; this is a pinned integration, not a stable upstream API claim.

## Committed Selection And Optional Offers

**Decision**: Extend the existing inventory internals with a detached projection of committed
validated selection and optional offers. Preserve the existing public inventory API. Resolve the
combined root/optional selection through the existing validator, then obtain a required-only inventory
for each distinct selected extension root at the same frozen commit.

**Evidence**: [Invoke-InventoryPreview.ps1](../../.github/skills/skill-library/scripts/Invoke-InventoryPreview.ps1)
owns committed inspection and cleanup; its public result omits inactive optional offers and file
hashes. The internal validated catalog already has exact versions, native folders, optional keys and
reasons. [Invoke-Archive.ps1](../../.github/skills/skill-library/scripts/Invoke-Archive.ps1) demonstrates
committed blob/mode/hash reads. [Invoke-VersionPreparation.ps1](../../.github/skills/skill-library/scripts/Invoke-VersionPreparation.ps1)
demonstrates recomputing a preview before applying a matching fingerprint.

**Rationale**: Optional selections choose separate extension roots, not every component in the combined
closure. Offers originate only on active components; newly exposed offers remain unselected. Required
overlap remains present inside each extension, with separate physical ownership.

**Alternatives considered**: A second graph parser, hyperlink inference, filtering a combined optional
inventory into an archive, or deduplicating resources across extensions would break existing ownership.

## Local Catalog And Artifact Inputs

**Decision**: Accept explicit existing local generated catalog files and trusted artifact directories.
Read catalog bytes directly; never invoke catalog fetch/search during preview. Locate a selected
candidate by the preceding adapter's `<id>-<version>.zip` convention, then independently verify its
digest, manifest identity and source evidence. Names are routing hints, not identity authority.
Require exactly one matching catalog record and one candidate per selected extension; duplicates
are blockers even when equal. Declined artifacts are never opened or downloaded.

**Rationale**: The prior adapter generates one-entry catalogs and prebuilt extensions. Several such
catalogs support the bounded optional-selection case without inventing a relationship catalog or
requiring public releases. URLs remain catalog provenance, not permission to fetch them.

**Alternatives considered**: Remote acquisition expands trust, redirect, authentication and failure
scope; rebuilding during installation changes the approved inputs. Both remain outside this increment.

## Delegate To The Current Upstream Archive Installer

**Decision**: Add a small isolated Python bridge around
`ExtensionManager(workspace).install_from_archive(archive_path, "1.2.3", priority=10, force=False,
archive_file=stream, expected_id=id, expected_version=version)`. Open a regular, unlinked selected ZIP,
hash and inspect that stream, rewind it, and pass the same open stream upstream. Require canonical
literal version equality as well as upstream identity/version validation.

**Evidence**: Installed `specify_cli.extensions.ExtensionManager.install_from_archive` at lines
3211-3296 accepts an existing stream and delegates safe extraction and installation. Its
`install_from_zip` method at lines 3445-3471 is a compatibility wrapper; new code will use the current
archive method. The manager compares versions semantically, so the wrapper must additionally enforce
the literal authored `X.Y.Z` value. The CLI has `--version`, URL `--from` and directory `--dev`, but no
local-ZIP flag.

**Rationale**: FR-007 requires reuse of upstream installation/registration, not a CLI-only transport.
This adapter preserves that owner without claiming long-term API stability. An incompatible signature
or version is a prerequisite blocker, never permission to substitute a custom extractor.

**Alternatives considered**: The compatibility alias adds no capability; `--dev` links development
content; `--from` introduces HTTP delivery and does not bind the positional ID as an expected ID.
Catalog CLI installation can select fallback sources and writes caches. None is needed for local apply.

## Accepted Runtime And Extension Shape

**Decision**: Require a valid initialized built-in Copilot skills-mode consumer and the generated
`skill-extension-pilot/1` command-only shape. Reject extension hooks, event subscriptions, adapters,
configuration templates and other executable integration declarations. Require one expected loading
command, read-only effect, exact runtime requirement and canonical resource/evidence members.

**Evidence**: Manager installation registers commands and can update registry/hook configuration. The
CLI separately calls event refresh and configuration scaffolding. Registration may load project
adapter Python; external adapter paths can also update profile-level trust state. Existing registry
parsers can normalize corrupt data to empty state, and command registration may skip occupied paths.

**Rationale**: Strictly parse and fingerprint runtime state before constructing a mutating manager.
Reject external adapters; any project adapter loaded for Copilot must match the installed trusted
built-in adapter bytes. Require no configured extension hooks/events. With no event/config additions,
the bridge deliberately does not invoke CLI event refresh or scaffolding. Verify exact command and
registry results afterward; an upstream success return alone is insufficient.

**Alternatives considered**: Copying CLI refresh wholesale broadens integration writes; accepting
arbitrary extension capabilities creates a different installer/security contract.

## Workspace, Scratch And Mode Boundaries

**Decision**: Keep operation evidence and extraction scratch inside the consumer's tool-owned operation
directory. Launch a fresh interpreter with `-I -B` and process-local `TMPDIR` set to that private
scratch before importing the manager. Do not edit host environment, package configuration or profiles.
Predict all runtime writes and shell-mode changes; reject any collateral change to existing files.

**Evidence**: Upstream extraction uses Python's temporary-directory facility without an explicit parent.
Catalog cache/download paths are workspace-local but avoidable through the local archive route.
Manager installation also traverses project script locations to set executable bits. Profile trust
updates are possible with external adapters, which this design excludes.

**Rationale**: The accepted mutation surface is payload, one generated skill per extension, runtime
registry/configuration and separate operation evidence. Existing unrelated content/modes must remain
unchanged. Reject a selected resource shape whose upstream mode normalization would violate its
recorded canonical modes. This remains a stable-workspace boundary, not a hostile-writer sandbox.

**Alternatives considered**: A hidden global cache, caller-independent system temp directory or broad
permission repair would violate previewed scope. Supplying an environment variable alone is not
runtime proof; later tests must observe actual scratch and write paths.

## Approval, Ownership And Recovery

**Decision**: Preview is detached generated evidence, not an executable supplied plan. Apply recomputes
it from original inputs, checks the reviewed fingerprint, records an operation before delegation and
verifies each result before proceeding. Existing payload, command targets and unknown ownership always
block, including same-version installations. A tool-owned lock coordinates only this orchestrator.

**Evidence**: Upstream can remove an unregistered occupied extension directory and is not atomic across
copying, registration and configuration. It has no encompassing installation transaction/lock.

**Rationale**: Preflight, before-call evidence and post-verification are necessary even with upstream
delegation. Failure/cancellation stops further work; previously verified extensions and ambiguous
partial files remain for deliberate reconciliation. An incomplete receipt blocks a new apply.

**Alternatives considered**: Automatic rollback, adoption, force replacement and resume would require
independent local-edit/shared-ownership policies. They are intentionally deferred, not compatibility
paths hidden inside the first-install feature.

## Research Exit

All technical choices above are resolved for this bounded plan. No new package, metadata schema,
consumer runtime or public service is required. The Python API coupling is deliberate and pinned.
Remaining work is implementation and approved validation, not a claim that runtime side-effect,
interruption or editor gates have passed. The [contract](./contracts/workspace-install.md) owns the
concrete interface and rejection rules; the [validation guide](./quickstart.md) owns later checks.
