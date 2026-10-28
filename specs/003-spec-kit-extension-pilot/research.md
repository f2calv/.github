# Research: Spec Kit Extension Pilot

**Date**: 2026-10-28. Target the existing pinned Spec Kit 1.2.3 Copilot skills-mode integration.

## Extension Boundary

**Decision**: Adapt an approved `skill-archive/1` ZIP, rather than change its byte contract or resolve
dependencies again. Preserve its canonical source bytes and embedded source manifest. Generate only
extension-specific metadata, a read-only command and build evidence.

**Rationale**: Feature 002 already owns committed required-only membership and source attribution.
The extension layout is a different consumer contract, not proof of compatibility inherited from ZIP.

**Alternatives**: A second metadata resolver duplicates authority; hand-authored copied skill bodies
break canonical ownership; relabelling the existing ZIP does not supply an extension manifest/command.

## Installed Manifest And Catalog Contracts

**Decision**: Use the installed runtime's `ExtensionManifest` and `ExtensionCatalog`, not invented
schemas. JSON is used as valid YAML for generated `extension.yml`, keeping serialization structured.
The manifest declares `schema_version: "1.0"`, extension identity/version, `effect: read-only`,
`requires.speckit_version: "==1.2.3"` and `provides.commands`.

The catalog has `schema_version` and an `extensions` mapping keyed by ID. One current record supplies
the exact version, description, download URL and SHA-256. The pinned runtime accepts exact current
selection through `--version`; historical releases are unnecessary for this one-version pilot.

**Evidence**: The installed code was inspected, then the real CLI accepted the generated manifest,
found the catalog entry and installed version 1.0.0. Upstream references at the pinned revision:
[manifest, catalog and registration](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/extensions/__init__.py)
and [exact-version selection](https://github.com/github/spec-kit/blob/5ea8b1cf0a38699340a38e00d02770308997d8c0/src/specify_cli/extensions/_catalog_versions.py).

## Local Discovery And Installation

**Decision**: Serve generated artifacts on loopback and configure one explicitly install-trusted
project catalog using `specify extension catalog add`. Project configuration replaces defaults;
no public catalog or artifact publication is needed.

**Alternatives**: `--dev` is useful for development but does not demonstrate archive download/digest
verification or catalog discovery. `--from` bypasses catalog selection. Neither is the acceptance path.

**Observed prerequisite**: A consumer fixture needs its Copilot integration manifest as well as
init options/integration settings. The initial incomplete fixture produced an event-refresh warning.
After adding the existing pinned manifest, an actual disable/enable cycle refreshed without it.
This is a minimal local fixture, not evidence of full project initialization or core-command loading.

## Command Loading And Safety

**Decision**: Generate `speckit.<id>.load`; the pinned Copilot integration renders
`/speckit-<id>-load`. Its body addresses installed resources explicitly, forbids original-checkout
fallback and reads references on demand. Copied instructions do not gain native `applyTo` activation.

**Evidence boundary**: Initial CLI registration and manual reads did not prove editor invocation.
The final validation record separately captures the owner's confirmation of native command selection,
automatic loader attachment and installed-only resource reads. This is owner-reported editor runtime
evidence, not discovery inferred from successful installation or an independently inspected read trace.

**Output policy**: A Linux-only, caller-controlled local adapter uses exclusive directory/files and
never overwrites existing output. After-reservation failure retains partial output. Do not copy the
original writer's stronger ownership/rollback claims onto this distinct pilot adapter.
