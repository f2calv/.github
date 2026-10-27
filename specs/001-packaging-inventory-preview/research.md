# Research: Packaging Inventory Preview

Resolved 2026-10-27 through read-only local research. No tests, source checkouts, installations
or network operations were performed. These decisions are design, not verified preview behavior.

## Trusted Rules and Committed Data

Decision: Invoke the current trusted tool bundle against inert input from one resolved commit.
Capture validator, reader, private helpers and bundled schemas as consistent trusted inputs for
the invocation. Do not load scripts or schemas from the requested source revision. Report that
rules come from the invoked tool bundle, separately from the content's source commit.

Rationale: [Read-SkillYaml](../../.github/skills/skill-library/scripts/Invoke-Validation.ps1#L33)
locates the reader beside the validator; schema paths are also relative to that trusted script.
Existing preparation validates staged data with the trusted validator. Trusted temporary tooling
must be separate from source payload and preserve these paths. Use Python `-I -B`, with no
snapshot import directory or inherited Python search path. Inventoried scripts remain inert.

Alternatives considered: Running historical validation executes payload. Reimplementing it creates
another authority. Reading working metadata mixes revisions. Preparation's working-input detector
includes local files and local ignore policy, contrary to committed-only reporting.

## Commit and Blob Access

Decision: Resolve `SourceRevision` once with `rev-parse --verify --end-of-options` and the commit
peel suffix. Reject unavailable/ambiguous input, including ambiguity warnings. All remaining
reads use resolved object IDs, `ls-tree -z` and binary `cat-file blob` output.

Rationale: Preparation's `Invoke-PreparationProcess`, `Invoke-PreparationGit`,
`Get-PreparationTree` and `Get-PreparationBaseline` demonstrate byte-safe process/tree/blob access.
Extract their common subprocess boundary, not release policy. Clear inherited `GIT_*` redirects,
disable replacements, lazy fetch, optional locks, fsmonitor and transport; pass explicit repository
location and process-local configuration. No global trust/config changes. Missing objects fail.

Alternatives considered: Archives can apply `export-ignore`/`export-subst`; checkout can invoke
filters and changes state; text reads corrupt binary content. Clones/worktrees need separate
approval and are unnecessary. Complete release/tag ancestry is not needed for one local snapshot.

## Discovery and Validation Scope

Decision: Inspect immediate child trees beneath `.github/skills` for sidecars; recurse only into
opted-in trees. Include defaults and exact external/notice paths from all opted-in records for
catalog-wide validation. Reject unsafe paths, link ancestors, symlinks, gitlinks and unsupported
modes before materialization. Accept regular-file modes `100644`/`100755` and retain mode identity.
Do not recursively inspect unconverted trees; an external declaration permits only its exact path.

Rationale: [Invoke-SkillValidation](../../.github/skills/skill-library/scripts/Invoke-Validation.ps1#L94)
checks every opted-in record/tree, including unselected ones. Missing or unsafe committed content
must not be hidden by early ignore filtering. Payload scope differs from validation scope.

Alternatives considered: Whole-repository materialization reads unrelated content. Selected-only
validation bypasses catalog-wide rules. Pre-filtering ignored files conceals validation failures.

## Snapshot-Only Ignore Eligibility

Decision: Use `check-ignore --no-index --stdin -z` on candidates with ancestor `.gitignore` blobs
from the chosen snapshot. Use temporary empty Git metadata initialized with an empty template,
and the inert data directory as its work-tree argument. Disable system/global configuration and
user excludes; no info/exclude, source objects/refs or populated index. Statuses 0/1 are normal.

Rationale: Git preserves nested patterns, directory exclusions and negation. Empty metadata avoids
host/local excludes and supports tracked-but-ignored files. This is a disposable matcher context,
not a source clone, registered worktree or alternate checkout. All temporary material is outside
the source worktree and removed on success/failure. None was created during planning.

Alternatives considered: Caller ignore checks mix local rules and normally skip tracked files.
Hand-written matching risks incompatible semantics. A populated index is unnecessary. Any actual
alternate source checkout still requires separate permission.

Ignored ordinary internal files are omitted. Ignored selected sidecars, entrypoints, external
files or notices fail. Ignore files/defaults are rule inputs, not automatically selected payload.

## Closure and Attribution

Decision: Use validator `SelectedIds` exclusively for membership. Its `-IncludeCatalog` result
also supplies `Catalog`, `Folders` and `Defaults`. Decorate membership with each root and every
active incoming edge; propagate root-ID sets over the validated DAG. Do not enumerate all paths.

Rationale: The validator rejects duplicate/unknown/unreachable optional choices and selected
cycles. Incoming edges plus root sets explain diamonds without exponential output. Canonicalize
repeated roots, but preserve duplicate optionals until validation rejects them. Use ordinal order.

Alternatives considered: Another closure resolver can diverge. A visited-only reason loses diamond
attribution. Full path enumeration is unnecessary. Hyperlinks are never inferred graph edges.

## Declaration Provenance

Decision: Retain strict raw defaults/sidecars before normalized catalog data. Record declaration
path and field/index for effective license, inherited/component notices and external files.
Equal-valued explicit overrides remain overrides. Deduplicate entries, not distinct reason tuples.

Rationale: Validation fills inherited license and merges notices. Normalized values cannot recover
their sources. Reuse its strict `Read-SkillYaml` parser for provenance, not textual guessing.

Alternatives considered: Equal strings do not prove inheritance. Merged notices lose declaration
locations. Neither approach proves redistribution rights; reporting remains declarations-only.

## Validation and Remaining Gates

Decision: Add one adjacent inventory Pester suite and extend the existing focused runner. Cover
shared process/reader changes with existing metadata/preparation suites. Synthetic fixtures own
any commits/tags. Real previews are read-only; test execution needs separate approval.

Rationale: The public surface is small but Git/filesystem and launch boundaries are safety-sensitive.
Negative, binary, cleanup and hostile-input scenarios matter more than an arbitrary benchmark.

Alternatives considered: Broad suites add unrelated prerequisites; another runner duplicates
existing infrastructure. No tests are authorized by planning itself.

No design clarification remains. Executable verification, Windows verification and future commit
or delivery permissions remain pending, not completed research outcomes.
