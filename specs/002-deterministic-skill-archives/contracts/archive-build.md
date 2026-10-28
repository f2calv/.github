# Contract: Local Skill Archive Build

**Contract identifier**: `skill-archive/1`

**Status**: Implemented and verified for the Linux tuple in the [validation guide](../quickstart.md).
This is not a loader-compatibility, rights or cross-runtime equivalence claim.

## Public Interface

Entry point: `.github/skills/skill-library/scripts/Invoke-Archive.ps1`.
Dot-sourcing is inert and exposes `Invoke-SkillArchive` without exiting the host. Both surfaces
use exactly these five parameters:

| Parameter | Default and behavior |
| --- | --- |
| RepoRoot | Invoked script's source repository; explicit repository path accepted. |
| SourceRevision | `HEAD`; local commit resolution only, then freeze the full resolved commit ID. |
| SkillName | No all-roots default; an array accepted only when it contains exactly one explicit nonempty native folder name. |
| OutputDirectory | No default; absolute new directory under an existing trusted parent. |
| PythonPath | `python3`; existing CPython on Linux with installed validator prerequisites. |

Missing required values fail noninteractively, rather than prompting. Reject repeated roots,
multiple roots and unknown parameters, including `OptionalSelection`, even if empty. There are
no archive-bytes-on-stdout, overwrite, append, preview/install or publication modes.

The object function returns the [success result](../data-model.md#output-result-and-checksum) or
throws a terminating categorized error. CLI success emits exactly one JSON object and exits zero.
CLI failure emits one sanitized categorized stderr message and exits nonzero, with no partial
success JSON. Caller-facing output/recovery paths are not embedded artifact metadata.

## Trusted Execution And Source Reads

Capture and hash the trusted invoked bundle listed in the [data model](../data-model.md#builder-identity),
then execute those captured bytes. Explicitly supply the original repository root and interpreter
when running the copied inventory: its copied-script default location is not the source repository.
Never execute historical source scripts to inspect their commit.

Call `Invoke-SkillInventoryPreview` with exactly one root and empty optional selections. Keep
catalog-wide validation, snapshot ignore semantics, external declaration checks and mandatory
notice checks unchanged. Do not filter an optional combined preview after the fact. Check the
result's selected root, empty selections and root/required-only active reasons before writing.

Use the existing byte-safe Git/process helper with NUL-delimited tree reads and literal path
handling at the returned commit. Verify path/mode matches, obtain blob object IDs from that tree
and read blobs without checkout or filters. Preserve arbitrary byte content and executable modes.
No inherited Git environment, lazy fetch, hooks or repository payload program may drive execution.

Private staging contains only validated source-relative paths and trusted tool inputs. Select
scratch outside the repository and Git administrative/common directories even when temporary
environment settings point inside them; reject unsafe scratch rather than trusting that setting.
Check staged payload sizes/digests again while writing. Clean inventory scratch before staging
handoff and all remaining owned scratch before reporting output success.

## Members And Layout

The archive contains:

```text
manifest.json
payload/<repository-relative eligible source path>
```

For example, a selected native entrypoint retains the path
`payload/.github/skills/<native-folder>/SKILL.md`; a root notice retains `payload/LICENSE`.
This prefix preserves the relative geometry among included files without making generated evidence
look like authored source. Required skill directories stay separate. Do not rewrite authored links,
sidecars or contents. Optional-only linked content may be absent; no claim of complete link closure
or extension installation compatibility follows from this layout.

Every payload member corresponds to exactly one inventory file; every inventory file appears once.
Shared owners/reasons remain in evidence, not duplicated members. The only generated member is
`manifest.json`; no directory members, checkout metadata or unlisted scaffolding are added.

Apply the inventory's safe-path and collision rules and reject generated/payload conflicts. Names
use `/`, strict UTF-8, no BOM, no absolute paths, empty/traversal components, backslashes, NUL or
surrogates. Do not normalize Unicode names or silently repair conflicting names.

## ZIP Byte Rules

Use stdlib `zipfile` over a new seekable binary file, not filesystem-derived `write()` metadata.

| Property | Required value |
| --- | --- |
| Compression | Stored method `0` for every member; no compression tuning. |
| Member order | `manifest.json` first, then payload paths ordered by unsigned UTF-8 bytes. |
| DOS timestamp | 1980-01-01 00:00:00, date word `0x0021`, time word `0`; no timezone conversion. |
| Creator system | Unix, numeric `3`, independent of host defaults. |
| Versions | `create_version=20`, `extract_version=20`; creator word `0x0314`, extraction word `0x0014`. |
| General flags | `0` for ASCII names, `0x0800` for non-ASCII UTF-8 names; no other flag bits. |
| External attributes | Source mode `0o100644 << 16` or `0o100755 << 16`; generated manifest uses `0o100644 << 16`; low DOS bits zero. |
| Internal attributes | Zero; volume and reserved fields zero. |
| Extra fields/comments | Empty member extra, member comment and archive comment. |
| CRC and sizes | Library-calculated CRC-32 and exact uncompressed/stored lengths. |
| Data descriptors | None: use a seekable stream and finalized local headers. |
| ZIP64/encryption | Disabled; reject outside limits instead of changing format. |

CPython resets supplied write flags internally. Use its conditional filename encoding, not a
private-method override to force UTF-8 flags on ASCII. Explicitly initialize all other fields.
Close the ZIP to write its central directory before hashing the complete file.

Reject more than 65,534 members including the manifest, names exceeding 65,489 UTF-8 bytes, or
predicted complete archive size exceeding 1 GiB. Without extras/comments/descriptors, predicted
size is 22 plus the sum of `76 + 2 * UTF8NameLength + ContentSize` for every member. Include the
canonical manifest's actual bytes in that calculation and require final length to match. These
conservative limits avoid ZIP64 sentinel/CPython thresholds; they are not the general ZIP maxima.

## Manifest Bytes And Digest

### Nested Evidence Shapes

All fields below are required, case-sensitive and non-null; objects reject unknown keys.
`SchemaVersion` is the integer `1`. `Builder` has exactly `Contract`, `ValidationRules`, `Files`
and `Runtimes`, with the first two strings fixed to `skill-archive/1` and `invoked-tool-bundle`.

| Field | Exact JSON shape |
| --- | --- |
| Builder.Files | Nonempty array of objects with exactly `Path` and `Sha256`, both strings. Paths are unique safe bundle-relative paths sorted by UTF-8 bytes; digests are 64 lowercase hexadecimal characters. |
| Builder.Runtimes | Object with exactly `PowerShell`, `Git`, `Python` and `PyYAML`. PowerShell, Git and PyYAML are nonempty version strings without local paths. Python is an object with exactly `Implementation` and `Version`, both nonempty strings; Implementation is `CPython`. |
| GeneratedMembers | Array containing exactly one object: `{"Path":"manifest.json","Role":"build-evidence","Mode":"100644"}`. It remains an array despite its single member. |

Root contains exactly string fields `Id`, `Version` and `Folder` from the selected inventory
component. Payload contains objects with exactly `SourcePath`, `MemberPath`, `Mode`, `Size`,
`Sha256`, `Owners` and `Reasons`: paths/mode/digest are strings, Size is a nonnegative integer
(not a boolean), and Owners/Reasons remain inventory arrays. Payload modes are `100644` or
`100755`. Components retains the existing inventory component-object shape, not a second schema.
OptionalSelections is always an empty array, and Limitations is the ordered string array below.

### Canonical Encoding

Use the [closed generated model](../data-model.md#embedded-manifest), not another authored sidecar.
Serialize with sorted string keys, compact `,`/`:` separators, unescaped Unicode, strict UTF-8,
no BOM and one trailing LF. Reject floats, nonfinite values, invalid Unicode and non-string keys.
Arrays remain arrays; payload and builder-file arrays use UTF-8-path order, components use existing
inventory ID order, and attribution arrays retain inventory order. Fixed limitations have a fixed
documented order. This encoding is contract-specific, not RFC 8785/JCS.

The fixed `Limitations` strings, in order, are:

1. `Local artifact only; no installation or publication was performed.`
2. `License and notice declarations do not establish redistribution approval.`
3. `Digests establish integrity comparison, not publisher authenticity.`
4. `Extension loading and native Windows behavior are not verified by this build.`

The source commit identifies committed defaults, ignore rules and catalog inputs; only eligible
payload files enter `Payload`. Builder files use logical paths relative to their captured skill
bundle, not source commit identity or workstation paths. Record exact runtime versions as distinct
build inputs. A newer runtime or trusted bundle is not the same complete input tuple.

After the ZIP is closed and synced, hash all archive bytes with SHA-256. Write the detached file
as exactly `<64 lowercase hexadecimal characters>  package.zip` plus LF. The filename is fixed so
the checksum is independent of its destination directory. Neither embedded manifest nor any
archive member contains the final archive hash. No signature or legal approval is implied.

## Output Safety

Require an existing stable trusted parent on a supported local Linux filesystem. Reject existing
destination entries of any kind, including empty directories, files and dangling links. Reject
destinations inside the entire source repository or any resolved Git administrative/common
directory, using component-aware containment rather than string-prefix comparisons. Missing parent
directories are errors; packaging does not create ancestry or modify caller-owned directories.

Traverse parent components with descriptor-relative directory opens and no-follow flags, then
reserve the leaf with exclusive `mkdir` and private permissions. Refuse ambiguous `.`/`..` paths.
Open the reserved directory without following links and record its identity. Create `.incomplete`,
`package.zip` and `package.zip.sha256` exclusively relative to that directory, recording each
successful creation immediately. A marker is temporary operational state, never archive content.

Follow the [lifecycle](../data-model.md#output-ownership-and-lifecycle): write/close/sync the ZIP,
write/close/sync the checksum, validate exact output entries, identities and hashes, clean all
owned scratch, remove the owned marker, sync directories and close required handles. Verify
expected state again before returning the buffered success object. The completed directory has
exactly the two promised regular output files and no marker.

On failure, unlink only ledger-owned entries whose identity, type, link count and expected content
still match, then remove the matching empty directory. Never use recursive output deletion.
Preserve replacements, foreign additions or changed content and report retained recovery locations.
If cleanup cannot complete, suppress success even when the pair appears complete. Retries always
refuse leftovers instead of adopting them or deleting them by filename.

Competing attempts to reserve the same destination are supported: one wins and the other fails
untouched. Concurrent modification inside the winner's directory is unsupported; detected
interference fails conservatively. This is not protection against hostile same-user writers,
privileged attackers, mount replacement or arbitrary network filesystem semantics. Identity checks
have races outside the stable-parent/exclusive-use assumption.

Partial files may be visible before completion. No atomic pair visibility, crash-atomic rollback
or power-loss guarantee is promised. A crash can leave an unmarked directory or a finalized but
unacknowledged pair; deliberate recovery inspection is required before choosing a new destination.

## Failure Categories

| Category | Examples |
| --- | --- |
| Prerequisite | Unsupported platform/interpreter, missing installed requirements or missing trusted bundle input. |
| Selection | Zero/multiple/repeated roots, optional-selection parameter, invalid required-only result. |
| Source | Unresolvable local commit or unavailable source objects. |
| Validation | Catalog/schema/dependency errors from existing validation. |
| Eligibility | Unsupported source mode, unsafe path, ignored mandatory file or member conflict. |
| Inspection | Failed committed tree/blob reads or unexpected staged content. |
| Archive | Unsupported limits, serialization/header mismatch, write/close/hash failure. |
| Output | Existing/unsafe destination, reservation race, failed exclusive create/sync or observed interference. |
| Cleanup | Temporary/output cleanup failure; retain ambiguous data and suppress success. |

Unknown internal errors become sanitized failures, not raw process stderr. Selection and unknown
parameter failures may be intercepted by the CLI boundary but must remain noninteractive and
must not create output. Diagnostics never echo payload bytes, credentials or configuration dumps.

## Compatibility And Non-Goals

Execution requires PowerShell 7.4+, CPython 3.11+, Git and installed PyYAML 6.0.3. Initially Linux
only; reject other operating systems/implementations before reserving output. Validation must
record actual tested runtime tuples. Minimum versions do not imply every tuple produces identical
bytes, and upstream source review does not substitute for observed byte checks.

Preserve the preview's optional-closure inspection and native library use. No new metadata fields,
component/repository version changes, tags, downloads, installations, rights approval, signing,
GitHub release assets or Spec Kit loader integration are delivered by this contract.
