# Data Model: Deterministic Skill Archives

**Status**: Implemented generated evidence model; no new authored metadata schema.
Observed runtime and verification limits are in the [validation guide](./quickstart.md).

## Archive Request

| Field | Meaning and validation |
| --- | --- |
| RepoRoot | Existing local repository; default is the invoked tool's repository, not caller location. |
| SourceRevision | Local revision, default `HEAD`; resolve once to a full commit and use only that commit afterward. |
| SkillName | Exactly one explicit nonempty native folder name; zero, duplicates or multiple values fail. |
| OutputDirectory | Absolute new directory with an existing trusted parent; no links, existing entries or source/Git containment. |
| PythonPath | Existing CPython interpreter with supported Linux filesystem APIs and installed PyYAML 6.0.3. |

There is no optional-selection, all-skills, overwrite, install, publish or version parameter.

## Required Payload Inventory

The existing inventory result remains the membership authority. `OptionalSelections` must be empty,
`Roots` must match the one requested native folder, and active component reasons may be `root` or
`required` only. Components retain exact `Id`, `Version`, native folder, entrypoint, reaching root,
incoming edge attribution and effective license/notice sources.

For every unique `Files[].Path`, the archive layer obtains a matching committed tree entry and
blob from `SourceCommit`. Unsupported modes or a mode/path mismatch fail; staged bytes never
override committed inputs. Required chains and diamonds do not duplicate physical members.

Optional metadata on selected components is still authored payload. It does not activate an edge,
add optional-only files or become an installation instruction executed by this builder.

## Builder Identity

| Field | Meaning |
| --- | --- |
| Contract | Versioned byte contract identifier `skill-archive/1`. |
| ValidationRules | Existing trust label `invoked-tool-bundle`. |
| Files | Strict UTF-8-path-sorted logical paths and SHA-256 values of captured trusted tool inputs; exact object keys/types are defined by the [nested evidence contract](./contracts/archive-build.md#nested-evidence-shapes). |
| Runtimes | Exact PowerShell, Git, CPython implementation/version and PyYAML versions using the same nested evidence contract. |

Capture the archive entry point/writer, inventory/validation scripts, Git helper, metadata reader,
both schemas and requirements file. A missing, changed-during-capture or unreadable required bundle
file fails. Invoke that captured bundle with an explicit repository root. Do not mix hashes of
one copy with execution of another, or include local installation paths in evidence.

Builder identity is an input separate from `SourceCommit`: newer invoked tooling may package an
older source commit. Runtime minima describe executable prerequisites, not proof of byte equivalence
across patched distributions or different versions. Only the approved observed matrix supports claims.

## Embedded Manifest

The generated manifest is a closed object with these fields:

| Field | Meaning |
| --- | --- |
| SchemaVersion | Generated evidence version `1`; never added to authored sidecars. |
| SourceCommit | Full resolved source commit identifier. |
| Root | Object containing selected component `Id`, `Version` and native `Folder`. |
| OptionalSelections | Always an empty array, making the required-only boundary machine-visible. |
| Builder | Captured trusted builder identity above. |
| Components | Existing selected component records, preserving attribution and effective declarations. |
| Payload | UTF-8-member-path-sorted array of source payload records below. |
| GeneratedMembers | A one-element array containing exactly the `manifest.json` record: `Path`, `Role=build-evidence`, `Mode=100644`; mode is a string. |
| Limitations | Fixed archive-specific statements for local-only output, declared terms, no rights/authenticity approval, and no installation/publication. |

Each payload record has `SourcePath`, `MemberPath`, `Mode`, `Size`, `Sha256`, `Owners` and `Reasons`.
`MemberPath` is exactly `payload/` plus `SourcePath`; it is not a consumer installation path.
`Mode` is `100644` or `100755`; `Size` is an integer byte count. Owner and reason collections
remain arrays even when empty or singleton; reasons retain declaration indexes and loading purpose.
The source commit is inherited from the manifest, not independently selectable per member.

The manifest does not contain its own size/hash or the archive hash. Its generated-member record
is descriptive, not self-referential. Canonical serialization is defined by the
[archive contract](./contracts/archive-build.md). No build timestamp, repository remote, caller
path, output location, temporary path or random value enters this object.

## Output Result And Checksum

A completed directory contains exactly `package.zip` and `package.zip.sha256`. The checksum file
contains the lowercase SHA-256 of the completed ZIP, two ASCII spaces, `package.zip` and one LF.

Success returns `SourceCommit`, `RootId`, `RootVersion`, `OutputDirectory`, `ArchivePath`,
`ChecksumPath`, `ArchiveSha256`, `PayloadCount` and `ArchiveContract`. Absolute local output paths
belong only in this caller-facing result, never inside the archive or its detached checksum.
No success object is returned before cleanup and finalization complete.

Failures have one category and an actionable sanitized message. Recovery messages may identify
operation-owned retained paths for deliberate inspection, but must not echo source content,
raw interpreter stderr, source configuration or credentials. Failure never includes a success
object, final artifact digest or a claim that a retained archive is complete.

## Output Ownership And Lifecycle

| State | Invariant and allowed transition |
| --- | --- |
| Requested | No persistent output; reject parameter/platform/path errors. |
| Prepared | Trusted bundle captured, inventory cleanup passed, payload staged and verified, manifest/limits calculated. |
| Reserved | Exclusive new directory, descriptor identity recorded, incomplete marker owned; no existing directory adopted. |
| Writing | Output files created exclusively; each creation and expected identity/content state enters the ownership ledger. |
| Verified | ZIP closed/synced, detached checksum written/synced, pair and exact entries verified. |
| Finalized | Staging/tool scratch removed, marker removed, directory/parent synced and required handles closed. |
| Completed | Only now return the sole success object. |
| Failed | No success result; remove only proven owned unchanged entries, otherwise retain and disclose recovery paths. |

The private ledger records directory/file device, inode, type, link count and expected content state.
Revalidate before finalization and cleanup; an unexpected entry, replacement or changed bytes makes
ownership uncertain. Do not recursively remove output. Refuse all existing destinations on retries,
including crash remnants. Catchable errors attempt cleanup; process death may leave partial output.

The trusted-parent/exclusive-use assumption is necessary: these checks are not a transactional
filesystem, hostile-writer isolation or crash-atomic multi-file publication. The output directory
can be visible before completion. A crash after finalization but before acknowledgment can leave
a valid but unacknowledged pair that still requires deliberate inspection.
