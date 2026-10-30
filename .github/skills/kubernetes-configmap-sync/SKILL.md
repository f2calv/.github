---
name: kubernetes-configmap-sync
description: 'Embed a complete reviewed non-secret UTF-8 file in one existing tracked ConfigMap data key. Use for JSON or JSONC appsettings, XML including KNX exports, plain text, configuration drift checks and local GitOps preparation. Not secret synchronization, deployment or live cluster mutation.'
argument-hint: '[source file] [check|sync]'
user-invocable: true
---

# Sync File To ConfigMap

Use the [script](./scripts/Set-ConfigMapFromFile.ps1) to replace **one existing `data` string**
in **one existing, single-document ConfigMap**. The source is authoritative: embed the complete
text, normalizing CRLF and CR to LF only. Preserve whitespace, comments within the source, ordering,
and trailing newlines. Do not parse and reserialize JSON or XML as the embedded value.

## Privacy And Approval

- ConfigMaps are not secret stores. Obtain explicit review that the entire source contains no
  secrets before passing `-ReviewedNonSecret`. If it contains credentials, stop and move them to
  the application's secret provider; never filter or silently redact a partial ConfigMap copy.
- User content or personal data requires explicit approval for the intended **private** GitOps
  destination. Establish repository visibility separately; neither file names nor
  `-ReviewedNonSecret` establish privacy or authorize publication.
- Never print, diff, summarize or send payloads through model tools. No payload in logs, process
  arguments, environment variables, scratch files, transcripts or test reports. Review sensitive
  source locally outside the model-visible transcript.
- Obtain approval for the particular target before a real write. Synchronization, commit, push,
  validation tests and deployment are separate permissions.

## Inputs And Prerequisites

PowerShell 7.4+, Git and Mike Farah `yq` v4 must be installed locally. No tool installation,
network access, cloud operation, commit or push is performed by the script.

`SourceRoot` is an explicit absolute directory, independent of the script installation path.
`SourcePath` must be inside it. `TargetRoot` must be an explicit absolute Git worktree root and
`TargetPath` must be inside it. All path ancestors, including ancestors above these roots, must be
ordinary directories rather than symbolic links or reparse points. The existing target must be
tracked, clean against HEAD and the index, and not assume-unchanged or skip-worktree.

| Input | Meaning |
| --- | --- |
| `SourceRoot` | Explicit absolute root containing the source and optional local data |
| `SourcePath` | Source-root-relative or absolute contained UTF-8 file |
| `TargetRoot` | Absolute GitOps checkout root |
| `TargetPath` | Checkout-relative or absolute contained existing manifest |
| `ConfigMapName` | Exact existing `metadata.name` |
| `ConfigMapNamespace` | Exact existing explicit `metadata.namespace`; no default inference |
| `DataKey` | Exact existing string key under `data` |
| `Format` | Explicit `Json`, `Xml` or `Text`; never inferred from a filename |
| `XmlRoot` | Optional required XML local root name; domain wrappers can require it |
| `LocalConfigPath` | Optional source-root-relative gitignored `.psd1` with the inputs below |
| `ReviewedNonSecret` | Required acknowledgement of the complete source review |
| `WhatIf` | Validate and construct/verify the candidate entirely in memory; do not write |

Use [the local-data template](./assets/sync.local.psd1.example). Copy it to `sync.local.psd1`
inside the caller's source root and add that populated name to the caller's `.gitignore` **before**
filling it in. Import uses `Import-PowerShellDataFile`, not execution. Unknown keys and non-string
values are rejected; explicit parameters take precedence. `SourceRoot`, approval and common
PowerShell parameters cannot come from local data. Existing caller-specific deployment data must
be mapped explicitly, not imported under incompatible key names.

## Workflow

1. Confirm the privacy review, approved source root, target repository visibility, exact name,
   namespace and existing key. Stop on ambiguity, a secret, or an immutable ConfigMap.
2. Invoke this skill's script by its discovered absolute path (never assume a sibling checkout).
   A synthetic invocation from a caller repository is:

   ```powershell
   & $SyncScript -SourceRoot 'C:\work\example-source' `
       -LocalConfigPath 'sync.local.psd1' -ReviewedNonSecret -WhatIf
   ```

3. `-WhatIf` checks source syntax, path containment, tracking/cleanliness, tool identity, target
   identity, size and candidate equivalence. It returns `Unchanged` if already equal, or reports
   the proposed replacement without writing. It is not a drift-failure exit code.
4. Obtain target-specific approval, then repeat without `-WhatIf`. Results are `Updated` or
   `Unchanged`; the command returns nonzero on failure. Only the target file may change.
5. Show `git diff --stat`, not the full diff. Capture `git diff --check` privately and report only
   its status: Git's diagnostic output can quote embedded content. Run approved repository
   manifest/lint checks with equivalent output discipline; obtain approval before tests.
6. Obtain separate commit/push approval. Let GitOps reconcile through its normal process; never
   apply, patch or edit the live ConfigMap. A local file update is not deployment validation.

## Implementation Boundaries

- Source bytes are strict UTF-8 (an optional UTF-8 BOM is treated as an encoding marker), at most
  1 MiB. JSON/JSONC allows comments and trailing commas. XML uses `XmlReader` with DTDs prohibited,
  a null resolver and a character bound. XML encoding declarations must agree with UTF-8.
- The aggregate decoded `data` and `binaryData` payload must fit 1 MiB. The input manifest has an
  additional 8 MiB processing bound. These checks do not replace API-server schema/admission checks.
- All `yq` input/output is in memory via UTF-8 `ProcessStartInfo` stdin and captured pipes.
  Arguments contain fixed expressions only; no source text, values or filenames are passed to
  `yq`. No process-wide encoding or environment changes are required.
- The candidate is generated from the parsed manifest. All surrounding **semantic** metadata,
  other keys and values must match exactly. YAML comments, presentation, quoting and anchors may
  be reformatted; do not use this tool if lexical preservation of the manifest is required.
  Multiple documents and duplicate YAML mapping keys are rejected.
- Extracted text must equal the normalized source ordinally, including its ending, and pass source
  validation again. No-change compares normalized text and leaves original target bytes untouched.
- Recheck paths, original bytes and Git state immediately before writing. Verify the written bytes
  and parsed result; restore original bytes on write/verification failure. The tool needs exclusive
  local access while running: it is not an atomic multi-process transaction or a crash-recovery
  mechanism. Do not use untrusted concurrently modified directories or concurrent editors.
- The script acknowledges a human review; it is not a secret/PII detector or repository visibility
  verifier. Errors suppress parser/tool payloads. Do not enable PowerShell tracing or debugging
  that dumps local variables.

## Validation And Consumer Migration

The complete local workflow and focused synthetic regression suite are provided; no live source,
private deployment coordinates, GitOps write or reconciliation is validated by creating this skill.

After explicit approval, run:

```powershell
& "$SkillRoot\scripts\Invoke-Tests.ps1"
```

The runner pins Pester 5.7.1 and uses a project-local disposable test area, not system temporary
storage. Fixtures are synthetic; Git and `yq` are exercised locally, with mocks for failure paths.
Do not install missing dependencies silently.

Repository-specific wrappers retain domain requirements and caller configuration. Keep existing
scripts/callers until their parameter mappings, namespace, privacy approval and behavior have been
validated; leave a colocated migration TODO in those wrappers. Do not claim this skill has migrated
existing automation simply because it is discoverable.

## Maintaining This Skill

- Recheck `yq` v4 stdin, duplicate-key detection and YAML/JSON round-tripping when `yq` changes.
- Recheck PowerShell/.NET UTF-8, XML and `ProcessStartInfo` behavior after runtime upgrades.
- Recheck Git clean/tracking flags and Kubernetes ConfigMap limits when those tools change.
- Keep these drift triggers as Markdown bullets: the central skill metadata regression requires
  at least one list item in this section.

Extend synthetic cases for every changed safety boundary before migrating another caller.

Retain explicit byte-array read overloads and ordinal BOM comparisons: PowerShell span conversion
can read into a copy, and culture-sensitive comparisons can treat a BOM as ignorable. Git's
`check-ignore` accepts file paths but rejects literal-pathspec magic; keep that invocation distinct
from commands that accept pathspecs.
