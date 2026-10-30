---
name: 'tooling-local-overrides'
description: 'Choose .gitignore, Git info/exclude or global excludes, and scope local-only Copilot instructions, skills and tool configuration. Use for environment-specific overrides, private guidance, ignore precedence and exclusion verification.'
---

# Local Environment Overrides

Separate what Git may publish, where an assistant should apply guidance, and what a tool
actually enforces. Choose each scope explicitly; none substitutes for the others.

## Prerequisites

Use an existing checkout, Git on PATH, and the user's stated target environment and paths.
Commands below use PowerShell and the synthetic absolute repository path `C:/work/example`;
substitute the intended absolute path. No installation or host-policy change is required.
Follow the shared [workflow](../../instructions/workflow.instructions.md) and
[GitHub guidance](../../instructions/github.instructions.md) for permissions and publication.

## Choose the Boundary

| Need | Mechanism | Scope and limits |
| --- | --- | --- |
| Team-wide untracked build output or generated files | Tracked `.gitignore` | Travels with the repository; not conditional on host or environment. |
| Untracked files used only in this checkout | Git-resolved `info/exclude` | Local Git metadata, not committed; inspect linked-worktree sharing. |
| Personal editor or OS noise across repositories | `core.excludesFile` | Personal cross-repository scope; change only with explicit consent and preserve existing configuration. |
| Local-only assistant guidance | Private profile/workspace instruction or ignored skill | Guidance scope is separate from Git publication scope; verify client discovery. |
| Environment-specific runtime behavior | Explicit environment marker plus supported tool configuration/overlay | Check the consuming process, precedence and actual operation; prose does not configure tools. |
| Conditional Git configuration | Git `includeIf` | Conditions select Git configuration only, not shell environment or Copilot rules. |
| Mandatory restrictions | Deterministic tool checks, CI or tool policy | Enforce at the actual operation; guidance and ignore rules alone cannot enforce policy. |

Default to the narrowest requested scope. Do not change global configuration, host policies,
or a shared customization authority to solve a clone-local need.

## Git Ignore Semantics

Ignore rules govern untracked-file handling. They do not hide tracked changes and are not a
security boundary: `git add --force` can bypass them. They do not guarantee exclusion from
assistant reads, editor search, Docker build contexts, packages, archives or synchronization.
Configure and verify each consumer's supported exclusion mechanism separately.

Precedence, highest first, is command-line patterns for commands that support them, applicable
`.gitignore` files, `info/exclude`, then `core.excludesFile`. A deeper `.gitignore` overrides
one higher in the tree; within a precedence level, the last matching pattern wins.
Check the winning source instead of assuming a newly appended local pattern wins.

Patterns are relative to their `.gitignore` directory; `info/exclude` and global patterns are
interpreted from the worktree root. A leading `/` anchors there, a trailing `/` selects a
directory, and `!` negates. Git cannot re-include a child while its parent directory remains
excluded. Keep the parent traversable and exclude its contents when exceptions are needed.

Examples for a root-level ignore source, not instructions to add all three:

```gitignore
/.local-overrides/
/.github/skills/example-local-guidance/
/.local-output/*
!/.local-output/README.md
```

The last pair keeps the parent traversable. Prefer an exact requested file or directory over
broad patterns such as `.github/`, `*.json` or `*local*`. Ignore files themselves must contain
no secrets or sensitive identifying names, even when untracked.

Never use `assume-unchanged` or `skip-worktree` as local override policy. If a target is tracked,
stop and choose a supported untracked overlay or obtain explicit approval for a deliberate
repository change. Do not automatically untrack, delete or run broad `git rm --cached` commands.

## Inspect Without Changing State

Capture status and the staged diff before editing; retain the baseline privately without
publishing sensitive contents. Use the same commands afterward without staging anything.

```powershell
git -C C:/work/example status --short --untracked-files=all
git -C C:/work/example diff --cached --binary --no-ext-diff
git -C C:/work/example ls-files -- .github/skills/example-local-guidance
git -C C:/work/example rev-parse --path-format=absolute --git-path info/exclude
git -C C:/work/example config --show-origin --show-scope --get-all core.excludesFile
```

Resolve metadata with `rev-parse`; never assume `.git` is a directory or construct its path.
Linked worktrees can share Git metadata and exclusion state: verify the resolved location
for each relevant worktree. Clone-local does not mean host-isolated, and these rules do not
automatically travel to another clone or machine.

Inspect only the relevant configuration key and winning ignore lines, not a full configuration
or environment dump. Origins and configured paths may themselves be sensitive; sanitize reports.
An unset `core.excludesFile` can still use Git's default global ignore location, commonly
`$XDG_CONFIG_HOME/git/ignore` or `$HOME/.config/git/ignore`; inspect only as needed.

Treat exit codes per command: `check-ignore` returns 0 for a match, 1 for no match, and 128
for a fatal error. `config --get-all` returns 1 when the key is absent, which is expected.
`ls-files` normally returns 0 even with no output; output, not that exit code, proves tracking.
Check `$LASTEXITCODE` immediately, before another native command overwrites it.

## Apply a Local-Only Override

1. Confirm the requested boundary, absolute checkout, exact paths and permitted behavior.
   Inspect existing guidance and supported tool configuration before choosing an overlay.
2. Inspect tracking and exclusion state with the commands above. If already excluded by a
   suitable rule, reuse it. Read the resolved exclude file and preserve every existing entry.
3. For clone-local content, add only the exact requested anchored entry to the resolved
   `info/exclude`, before creating any private data. Do not rewrite global configuration.
   If a broader change is required, stop for explicit approval rather than silently widening it.
4. Verify the intended match and a nearby nonmatch using synthetic paths before creating the
   guidance or overlay. Neither path needs to exist for pattern diagnosis.
5. Create only the approved private content. Keep credentials in the user's approved secret
   mechanism, not in instructions or skills. Configure runtime behavior through the consuming
   tool's supported local overlay and explicit non-secret environment marker.
6. Verify Git publication scope, assistant discovery and runtime behavior independently.
   Recheck status and the staged diff against the baseline. Report sanitized evidence.

For the example customization directory:

```powershell
git -C C:/work/example check-ignore -v -- .github/skills/example-local-guidance/SKILL.md
git -C C:/work/example check-ignore -v -- .github/skills/example-shared-guidance/SKILL.md
git -C C:/work/example ls-files -- .github/skills/example-local-guidance
git -C C:/work/example status --short --untracked-files=all
git -C C:/work/example diff --cached --binary --no-ext-diff
```

Expect the intended resolved `info/exclude` source and exact pattern for the first probe,
exit code 1 and no match for the second, and no tracked files for the local directory.
If the neighbor matches, investigate the winning rule; do not remove someone else's exclusion.
Normal `check-ignore` does not report tracked paths. Use `check-ignore -v --no-index -- <path>`
only to diagnose how patterns would match regardless of the index; a match there does not
prove that a tracked file is protected. Keep the separate `ls-files` check.

## Scope Assistant Guidance

Instruction `applyTo` globs match paths, not environment expressions. A skill's description
supports discovery, not an enforceable automatic environment condition. Do not invent
frontmatter fields that promise host selection.

Use a private profile instruction for personal guidance or an ignored workspace instruction
or skill when supported by the client and the repository's customization rules. Prefer a
separate supported local instruction location over editing tracked shared guidance.
User profiles can roam or synchronize, so profile placement alone is not machine isolation.
Inspect junctions and symlinks before editing: a profile path may point into the central shared
authority and change it for every consumer.

Put a scope guard at the beginning of local guidance, using synthetic values such as:

```text
Apply only when the user identifies the target environment as example-local and the
approved non-secret marker EXAMPLE_LOCAL_ENV equals example-local in the consuming process.
If either check is absent or disagrees, stop and request confirmation before applying overrides.
This guidance does not change tool configuration or authorize host-policy changes.
```

Verify only the specific marker, never dump the environment. Use the user's stated environment,
not VPN status, network reachability, usernames or inferred employer/device identity.
Treat the guard as assistant guidance; a tool-side check must enforce a mandatory restriction.
For Git configuration, `includeIf` may select by repository directory or branch, but it is not
a mechanism to set process environment variables or activate assistant instructions.

Do not claim ignored skills are automatically discovered. Clients may honor ignored files
differently. Check VS Code Chat Diagnostics for the actual file and then verify an actual
invocation separately. Reload only when needed after a discovery change. If unsupported,
use a supported private location or explicit attachment; do not force-add private guidance.

## Acceptance and Rollback

* The target is untracked, its intended ignore source wins, and the nearby public path is not ignored.
* Existing exclusions and global configuration are preserved; the staged diff is byte-identical.
* Status shows only the approved public edits; private content is absent from publication paths.
* Diagnostics and an invocation confirm guidance loading; the scope guard matches only the
  confirmed environment, including an explicit refusal outside that scope.
* A safe tool-specific check confirms effective configuration at the consuming process or
  build boundary. Required enforcement is independent of assistant compliance.

On failure, remove only rules and files introduced by this operation, with approval before
deleting private data. Do not auto-untrack files or remove pre-existing rules. Removing an
ignore rule can expose private files as untracked: relocate or secure them first and recheck
status and the staged diff. Roll back only your own supported overlay changes.

## References

* [Git ignore precedence and pattern format](https://git-scm.com/docs/gitignore)
* [Git check-ignore diagnostics](https://git-scm.com/docs/git-check-ignore)
* [Git metadata path resolution](https://git-scm.com/docs/git-rev-parse)
* [Git conditional configuration includes](https://git-scm.com/docs/git-config#_conditional_includes)
* [VS Code custom instructions](https://code.visualstudio.com/docs/copilot/customization/custom-instructions)
* [VS Code agent skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills)

## Maintaining This Skill

* Recheck Git precedence, negated-parent behavior, exit codes, default global excludes and
  `--git-path` resolution when supported Git versions or linked-worktree behavior change.
* Recheck VS Code discovery locations, ignored-file handling, Diagnostics, invocation and
  profile synchronization when the client or customization format changes.
* Recheck marker propagation, overlay precedence and enforcement at the actual consumer when
  shell, container, build or tool configuration behavior changes.
