# Data Model: Spec Kit Extension Pilot

## Trusted Source Archive

Use the existing [archive contract](../002-deterministic-skill-archives/contracts/archive-build.md)
and an expected SHA-256 obtained from its approved build. This adapter is not a general untrusted-ZIP
importer. It checks digest, required-only evidence, safe unique paths, member count, modes, lengths,
payload hashes, root identity and the required root entry before reserving output.

Source component/dependency/license declarations stay unchanged. `source-manifest.json` preserves
the original manifest bytes; it is not rewritten into extension membership or a rights-clearance record.

## Generated Extension

- `extension.yml`: JSON-compatible YAML accepted by Spec Kit 1.2.3. Required sections are
  `schema_version`, `extension`, `requires` and `provides`. Identity/version derive from the source root.
- `commands/load.md`: generated read-only wrapper, declaring the installed root and external
  instructions, retaining source-relative links beneath `resources/library/`.
- `resources/library/<SourcePath>`: exact source payload bytes with declared source modes.
- `source-manifest.json`: exact source manifest bytes.
- `extension-build.json`: `Contract=skill-extension-pilot/1`, `SourceArchiveSha256`, `SourceCommit`,
  `Root` and `SpecKitVersion=1.2.3`. This binds the input artifact, not publisher identity or rights.

The extension artifact is distinct from `skill-archive/1`; it makes no additional complete-byte
reproducibility guarantee for the wrapper format or other runtimes.

## Generated Catalog

`catalog.json` contains `schema_version="1.0"` and one `extensions` entry keyed by root ID.
The entry derives `name`, `description`, `version`, `download_url`, `sha256`, `requires` and `provides`.
The generated description identifies a loading command; it does not duplicate canonical guidance.
Do not invent publisher/verification claims or manually maintain dependency declarations here.

The sibling checksum contains the final ZIP's lowercase SHA-256, two spaces, artifact filename and LF.
There is no circular archive hash in the ZIP. Expected digest comparison is not authentication.

## Consumer State And Verification

Spec Kit owns its local registry, catalog cache, installed extension and generated Copilot skill.
No new installer inventory schema is introduced. Record actual changed surfaces and keep them local.
The verified input-to-artifact chain is separate from those consumer files.

Generation, catalog discovery, installation, registration, manual resource reads and editor invocation
are separate verification states. Only an observed editor invocation can close the last state.
