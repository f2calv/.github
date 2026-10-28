# Contract: Local Spec Kit Extension Pilot

## Public Adapter

[Invoke-Extension.ps1](../../../.github/skills/skill-library/scripts/Invoke-Extension.ps1) exposes
the inert dot-sourceable `Invoke-SkillExtension` function and a CLI with four explicit parameters:

| Parameter | Meaning |
| --- | --- |
| `ArchivePath` | Existing trusted local `skill-archive/1` ZIP, at most 64 MiB. |
| `ArchiveSha256` | Expected lowercase 64-hex digest from the approved source build. |
| `OutputDirectory` | New absolute directory under an existing unlinked trusted parent outside source. |
| `BaseUri` | Absolute HTTPS or loopback HTTP hosting base ending in `/`, without credentials/query/fragment. |

The adapter is Linux-only and installs nothing. Payload members are bounded to 16 MiB each and
64 MiB total. It validates source evidence before reservation; optional selections, unsafe/duplicate
paths, unknown members, absent root guidance and inconsistent hashes fail as `Input`.

## Output And Failure Behavior

Success returns one object, or one CLI JSON document with exit zero, containing `RootId`,
`RootVersion`, `Command`, `ArchivePath`, `ArchiveSha256`, `CatalogPath` and `ChecksumPath`.

The new output directory contains `<id>-<version>.zip`, its `.sha256` and `catalog.json`.
See the [data model](../data-model.md) for member layout and the distinction from the native archive.

Exclusive reservation/file creation refuses existing output. `Output` failures after reservation
retain partial data and name its recovery location; no success or digest object is emitted. Never
recursively delete, overwrite or silently adopt that directory. Use stable inputs, a trusted parent
and exclusive caller use. No crash-atomicity, hostile-writer isolation or rollback guarantee is added.

## Spec Kit Consumer Interface

Configure the approved local generated catalog through `specify extension catalog add <url>
--name local-pilot --install-allowed`. Project catalog configuration replaces the default catalogs.
Use `specify extension search <id>` and `specify extension add <id> --version <version>` without force.
No custom installer, core override, automatic install hook or optional download is introduced.

Manifest command `speckit.<id>.load` registers as `/speckit-<id>-load` in the pinned Copilot skills-mode
integration. Its generated body reads installed canonical root/instructions and relevant resources;
it must not fall back to source/profile copies or execute payload scripts. Missing conditional peer
links are reported as unavailable; they are not inferred dependency edges or implicit install permission.

## Acceptance Evidence

Use the [validation guide](../quickstart.md). A registry entry, generated skill file, hash comparison
or manual file read cannot establish native editor discovery/invocation. Preserve that gate as pending
until the command is invoked in the consumer's actual Copilot session and installed resource reads are observed.
