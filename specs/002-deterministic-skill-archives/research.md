# Research: Deterministic Skill Archives

**Date**: 2026-10-27

**Status**: Design decisions complete; no runtime probes or tests performed.

## Required-Only Integration

Decision: Require one explicit native root. Call `Invoke-SkillInventoryPreview` with that root and
an explicitly empty optional selection; consume its `SourceCommit`, `Components` and `Files`.
Reject any optional edge in the returned active reasons as an internal contract failure.

Rationale: The [public inventory API](../../.github/skills/skill-library/scripts/Invoke-InventoryPreview.ps1)
already decides eligible committed membership, modes, notices and attribution through the existing
validator. Its public result is emitted after inspection cleanup. The archive operation can use
that result without widening the preview's contract or writing a second graph resolver.

Alternatives considered: Reimplementing closure is rejected because metadata semantics would drift.
Treating a combined optional preview as a package is rejected by the user's package boundary.
Optional metadata remains advisory; shared files and independently required targets remain included.

## Source And Trusted Tool Identity

Decision: Capture the invoked archive/inventory/validation tool bundle into private scratch,
including helpers, schemas and requirements. Hash and invoke the same captured bytes with explicit
repository/interpreter arguments. Record those logical bundle paths/hashes and exact runtime
versions in the manifest, not absolute local paths or host identity.

After inventory cleanup succeeds, resolve each listed path/mode through NUL-delimited tree reads
at the returned full commit ID and read its blob with the existing
[Git helper](../../.github/skills/skill-library/scripts/Git-Process.ps1). Stage committed bytes in
private scratch and hash them; no filter, checkout, hook or historical program execution occurs.
Object loss fails without lazy fetching. The fixed source commit identifies defaults, catalog and
ignore inputs even when those inputs are not themselves payload members.

Rationale: `ValidationRules=invoked-tool-bundle` is a trust label, not a content fingerprint. The
source commit may differ from trusted build tooling. Snapshotting the full execution bundle binds
the actual rules to evidence while keeping source payload inert and caller Git state unchanged.

Alternatives considered: Source commit alone cannot identify uncommitted invoked tools. Executing
historical build scripts is unsafe. Extending the public preview to return payload bytes is not
needed. Host paths, remotes and timestamps would leak local details and harm reproducibility.

## ZIP Library And Byte Contract

Decision: Use CPython stdlib `zipfile`, `ZIP_STORED`, explicit `ZipInfo` fields and a seekable
new binary file. Use fixed DOS epoch, Unix creator/modes, no extra fields/comments, no directory
entries and no ZIP64. Put generated `manifest.json` first, followed by `payload/<source-path>`
members ordered by strict UTF-8 path bytes. See the [complete byte contract](./contracts/archive-build.md).

Rationale: No new dependency or custom ZIP engine is needed. Stored entries avoid compressor drift.
The source-relative payload prefix retains relative native links among included files and separates
generated evidence from all source paths. Optional-only links may remain unresolved; this is not
an installer or a promise to make every Markdown link resolvable.

Alternatives considered: `.NET ZipArchive` uses a platform-dependent creator field with less public
control. Deflate needs additional compressor identity and version guarantees. Tar/gzip adds
different ownership/header normalization and offers no current consumer advantage. A flat package
layout would break source-relative references. Hand-writing ZIP headers is unnecessary complexity.

CPython resets `ZipInfo.flag_bits` when writing. Accept the library's documented/source-observed
conditional encoding: ASCII names have flags zero; non-ASCII names use UTF-8 with bit `0x0800`.
Do not override private APIs merely to force that bit for ASCII. Source inspection at CPython
3.11.14 and 3.14.0 supports this choice but is not cross-runtime verification.

Conservative limits avoid CPython's ZIP64 threshold and its `file_size * 1.05` preflight behavior:
65,534 total members, names at most 65,489 UTF-8 bytes and predicted complete size at most 1 GiB.
Calculate header/name overhead plus manifest and payload sizes before reserving persistent output.

## Canonical Evidence And Integrity

Decision: Serialize manifest string-keyed objects using sorted keys, compact separators, UTF-8,
no ASCII escaping, no nonfinite values, and exactly one LF. Use integers, not floating-point values.
Arrays have explicit order; retain inventory attribution array order. This is contract-specific
canonical JSON, not a claim of RFC 8785 conformance. SHA-256 values are lowercase hexadecimal.

The embedded manifest inventories payload hashes only. It never contains its own hash or the final
ZIP hash. Compute the completed ZIP hash externally and write a detached checksum. Do not copy the
preview's inventory-only limitation text into archive evidence as if it described this new operation;
use explicit archive limitations that preserve rights, authenticity and installation boundaries.

Rationale: This avoids circular hashing and permits independent inspection without another
authored metadata source. Exact interpreter/tool versions are recorded build inputs; different
recorded builder tuples may legitimately yield different archive bytes.

Alternatives considered: An archive digest inside that archive is self-referential. Pretty-printing
or host-supplied paths/times adds avoidable byte variability. A checksum is not a signature, rights
approval or immutable published release provenance.

## Output Reservation And Failure Safety

Decision: Require an absolute new output directory beneath an existing trusted parent, outside
the source repository and Git administrative/common directories. Reject links in parent ancestry.
Use Linux descriptor-relative traversal with no-follow directory opens and exclusive `mkdir`.
Create an incomplete marker and both output files exclusively; track owned identities/content.

Close/sync the archive, compute and write the checksum, validate the pair, clean all scratch,
then remove the owned incomplete marker and sync final directories before reporting success.
Revalidate staged bytes against their recorded sizes/hashes while writing. Failures remove only
provably operation-owned unmodified entries; preserve ambiguous files and report recovery paths.
Neither a familiar filename nor an incomplete marker grants ownership of existing contents.

Rationale: A competing reservation gets one winner without overwriting an empty directory. Readers
must wait for successful completion; partial files may be visible during construction. Catchable
failures get conservative cleanup, while crashes may leave directories that later runs refuse.

Alternatives considered: `os.rename` can replace an existing empty destination directory on Unix;
checking existence first races. `os.replace` deliberately overwrites. `renameat2(RENAME_NOREPLACE)`
adds a native boundary without a requirement for atomic directory visibility. Two output renames
cannot provide a filesystem-wide transaction. Blind recursive rollback can erase foreign content.

The threat model requires stable trusted ancestry and exclusive use of the reserved directory.
Observed interference suppresses success and preserves uncertain data. It does not claim protection
from hostile same-user writers, privileged attackers, mount changes or unverified network filesystems.
Stat/hash checks do not remove every race against those actors. Native Windows needs a separately
designed reparse-point/handle strategy; do not silently emulate Linux checks with weaker path logic.

## Validation And Approval Boundaries

Decision: Keep the existing Pester runner and add one adjacent synthetic archive suite later.
Reuse fixture helpers where suitable, require nonzero counts, and independently inspect ZIP
headers, membership, manifest and checksums. Scale tests to required/optional overlap, binary/mode
handling, reproducibility, output races, injected failures and source-state preservation.

Rationale: The first feature has no real required edges; synthetic chains and diamonds are needed.
Prior passing tests do not establish this new writer's behavior. Local Windows remains unverified.

Alternatives considered: Building real archives now or automatically rerunning tests exceeds this
planning request. Adding a separate test framework or mandatory host installation is unnecessary.

## Authoritative References

- [Python ZIP API](https://docs.python.org/3.11/library/zipfile.html) and
  [CPython 3.11.14 ZIP writer](https://github.com/python/cpython/blob/v3.11.14/Lib/zipfile.py).
- [CPython 3.14.0 ZIP writer](https://github.com/python/cpython/blob/v3.14.0/Lib/zipfile/__init__.py)
  for comparison, not a supported-version equivalence claim.
- [PKWARE ZIP specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).
- [Python JSON encoding](https://docs.python.org/3.11/library/json.html) and
  [hashlib](https://docs.python.org/3.11/library/hashlib.html).
- [Python filesystem APIs](https://docs.python.org/3.11/library/os.html),
  [Linux open semantics](https://man7.org/linux/man-pages/man2/open.2.html),
  [rename semantics](https://man7.org/linux/man-pages/man2/rename.2.html) and
  [directory synchronization](https://man7.org/linux/man-pages/man2/fsync.2.html).
- [.NET 10 ZIP entry writer](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.IO.Compression/src/System/IO/Compression/ZipArchiveEntry.cs)
  and its [Unix creator fields](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.IO.Compression/src/System/IO/Compression/ZipArchiveEntry.Unix.cs).

All initial design questions are resolved. The implementation and approved checks must still
demonstrate the chosen contract; the references do not constitute passing runtime evidence.
