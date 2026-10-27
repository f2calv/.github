# Command Contract: Packaging Inventory Preview

Implemented local interface; verification evidence and remaining gates are in the
[validation guide](../quickstart.md). Covers FR-001 through FR-012 in the
[specification](../spec.md); record details are in the [data model](../data-model.md).

## Invocation

Entry point: `.github/skills/skill-library/scripts/Invoke-InventoryPreview.ps1`.
Dot-sourcing exposes `Invoke-SkillInventoryPreview` with the same parameters, returning one object
instead of JSON. Dot-sourcing itself performs no preview or process exit.

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `RepoRoot` | string | Repository containing invoked script | Local source repository, independent of caller directory. |
| `SourceRevision` | string | `HEAD` | Unambiguous locally available revision resolving to one commit. |
| `SkillName` | string array | Empty | Native roots; empty selects all opted-in records. |
| `OptionalSelection` | string array | Empty | Explicit reachable `component-id/selectionKey` edges. |
| `PythonPath` | string | `python3` | Existing Python 3.11+ interpreter with PyYAML 6.0.3. |

No apply, archive, install, export, bump or publication switches. No network/provisioning. Callers
may explicitly redirect JSON outside managed source content; the command creates no inventory file.
A historical content revision never chooses historical executable tooling.

## Success

Script invocation exits 0 and emits exactly one complete JSON object to stdout; the object function
returns the corresponding object. No native-process/debug/progress text enters stdout.

| Field | Contract |
| --- | --- |
| `SourceCommit` | Full resolved source commit ID, also attributed on components/files. |
| `ValidationRules` | `invoked-tool-bundle`; trusted validator, reader and bundled schemas. |
| `Roots` | Expanded unique native roots, ordinally sorted. |
| `OptionalSelections` | Validated explicit identifiers, ordinally sorted. |
| `Components` | Unique included components ordered by ID with location, license, notices and reasons. |
| `Files` | Unique eligible files ordered by path with mode, owners and reasons. |
| `Limitations` | Exclusion of local edits and of package, release, rights and delivery approvals. |

Arrays remain arrays for zero/one element. Identical commit, selections and trusted rules produce
identical membership, reasons and review order. Exclude timestamps, elapsed times, temporary paths,
payload bodies and full metadata documents.

## Validation and Membership

- FR-001, FR-003, FR-004: Reuse `Invoke-SkillValidation -IncludeCatalog` on inert snapshot data.
  Preserve strict parsing, exact pins, native alignment, catalog-wide validation and existing
  cycle/reachability rules. `SelectedIds` alone owns membership.
- FR-002: Resolve once; all declarations/defaults/content use that commit. Missing local objects,
  invalid revisions and ambiguous names fail without fetching or changing checkout.
- FR-005, FR-008: Preserve every root and active incoming edge reason. Shared components/files
  appear once with all owners/reasons; ordinary hyperlinks add nothing.
- FR-006, FR-007: Include eligible committed regular internal files and mandatory external/default/
  component notices. Only snapshot ignore rules apply. Ignored ordinary internal files are omitted;
  ignored mandatory files fail. Defaults and ancestor ignore files are not automatically payload.
- FR-010: Use ordinal ordering, not locale-dependent or directory order. Existing case-collision
  rules apply. Raw parsed declarations supply attribution, not an alternate validation decision.

Effective license reporting distinguishes explicit overrides from inheritance even for equal values.

## Failure

FR-009: Script invocation exits 1 with a sanitized category and corrective guidance on stderr.
Stdout contains no success object/partial inventory. The object function throws a sanitized
terminating error; it never exits the host or returns a success-shaped failure record.

| Category | Examples | Corrective action |
| --- | --- | --- |
| `Prerequisite` | Missing executable or supported Python/PyYAML. | Supply already-installed trusted tools. |
| `Source` | Missing/ambiguous commit or local object. | Supply a valid locally available revision. |
| `Validation` | Invalid catalog, exact pins, paths, cycles or selections. | Correct authoritative declarations/source, then select its commit. |
| `Eligibility` | Mandatory entrypoint, sidecar, external file or notice ignored. | Correct snapshot rules or declarations. |
| `Inspection` | Blob/process/I/O failure or unsupported source entry. | Restore readable safe source; no working-file fallback. |
| `Cleanup` | Temporary context cannot be removed. | Perform deliberate local cleanup; no success claim. |

Do not relay raw subprocess stderr, payloads, environment dumps or credentials. Return bounded
corrective context; process failures must not become partial output.

## Safety and Review Boundaries

FR-011: Success/failure leave source files, untracked content, index, branch, commits, tags and
repository/global configuration unchanged. No payload execution, advisory tooling, filters, hooks,
lazy fetch, transports or source checkouts. Temporary inert data and empty matcher metadata live
outside the worktree, use no source refs/objects, and are always cleaned up. Cleanup failure is
reported rather than silently retaining material or returning success.

FR-012: The result is not immutable provenance, rights clearance, a package, installation state,
release approval or publication evidence. File/artifact digests, release history and installation
ownership remain separate future work.
