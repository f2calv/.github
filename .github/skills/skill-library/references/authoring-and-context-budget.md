# Authoring and Context Budget

How to write, split and audit instructions and skills so that context cost stays proportionate as
the library grows. Measure with `scripts/Measure-CustomizationContext.ps1`; the structural rules are
enforced by `.scripts/tests/Skills.Tests.ps1`.

## Cost Model

| Surface | Loaded | Budget |
| --- | --- | --- |
| `applyTo: '**'` instructions | Every request | About 4k tokens combined |
| Scoped instructions | Agent host: listed with their `applyTo`, read when the agent works on a matching file | About 5k tokens per typical file |
| Skill `description` | Every session, for every skill | 600 characters each |
| `SKILL.md` body | When the skill is invoked | 16 KB |
| `references/`, `examples/`, `templates/` | Only when the skill links and the agent reads them | Unbounded |

Push content down this table: an always-on line costs the most, a reference line the least.

In agent-host sessions only always-on instructions are guaranteed to be in context; a scoped file
takes effect only if the agent reads it from the listing, which a probe showed it may skip for a
routine file. Keep any rule that must never be missed always-on, and give a scoped file a
description that makes its relevance obvious from the listing.

## Loading Routes

- Agent-host sessions read workspace customizations only from their starting folder, so other
  repositories need the `~/.copilot/` links; never remove them to fix duplicates. Before VS Code
  1.144.0, those sessions loaded linked instructions twice (microsoft/vscode#342394).
- Verify loading from evidence, not from the customization view: start a throwaway session in a
  consumer repository after a VS Code restart, count a unique heading in its `system.message` event
  under `~/.copilot/session-state/<id>/events.jsonl`, then delete the session. Agent sessions
  discover `~/.copilot` only when VS Code starts.
- Extension-contributed instruction packs load by `applyTo` alongside the shared set and cannot be
  disabled file by file. Measure their overlap and recommend the narrowest pack, as the README does
  for HVE Core.

## Instructions

- Always-on files hold invariants only: short rules an agent must apply without being asked. Move
  procedures, command sequences, layouts and examples into the owning skill and leave a one-line
  pointer.
- Scope `applyTo` to the files a rule governs. When one section serves a narrower path, split it into
  its own file, as the README rules are split from general Markdown rules, or move it into a skill
  and add a pointer to a broadly loaded file. Avoid scopes that match every build file
  (`**/*.csproj`, `**/*.props`) or configuration file for a single section's sake.
- Avoid globs anchored to one layout, such as `src/**/*.yaml`, which fire in unrelated repositories;
  scope to the distinctive folder or filename instead.
- Condense by removing repetition, not rules. Compare the rule list before and after; a condensing
  pass can silently drop rules that only a deliberate re-read catches.

## Skills

- `description`: what the skill does, a `Use when`/`Use for` trigger, and the neighbouring skill
  that owns an adjacent concern ("CLI parsing belongs to dotnet-cli"). Never a keyword list.
- Front matter: unquoted `name`, single-quoted `description`, and no default-valued fields such as
  `user-invocable: true`.
- `SKILL.md` carries purpose, modes and boundaries, a numbered workflow whose steps state the
  decisive rules and link to detail, and `## Maintaining This Skill`. Long procedures,
  troubleshooting, worked examples and real-world inventories belong in `references/` or
  `examples/` from the first version, not after the file outgrows its budget.
- When a rule depends on agent compliance that harnesses or extensions may override, such as commit
  attribution, enforce it with a tested script that the rule calls, not with a longer procedure.
- Keep reusable mechanics in the central owner and repository-specific policy, coordinates and
  automation in a thin local adapter. Retain a separate local skill only when its invocation adds
  domain behavior; otherwise use repository instructions or a linked operational profile.

## Splitting Safely

1. Move text essentially verbatim into `references/<topic>.md`, each with one H1 and a purpose line.
2. Add one level to relative links (`../../instructions/` becomes `../../../instructions/`).
3. Search all available consumer repositories for `<skill-id>/SKILL.md#` links and plain skill-name
   references. Keep linked headings or update the links; when renaming, migrate every caller to the
   canonical name, including local adapters that stop if it is unavailable.
4. Keep each rule in one file; replace a duplicate with a link.
5. Compare the skill's total Markdown size before and after: it should stay level or grow slightly.
6. List any newly linked instruction file in the sidecar's `externalFiles`, then run
   `Set-SkillVersion.ps1`. Changing an instruction file bumps every skill that bundles it.
7. Write files with LF endings; editors and tools on Windows can introduce CRLF.

## Audit

Work top-down and commit each batch separately:

1. Run `Measure-CustomizationContext.ps1` and check the loading route.
2. Trim always-on instructions to invariants.
3. Narrow or split the scoped instructions with the highest per-file totals.
4. Split `SKILL.md` files over budget, largest first.
5. Review descriptions for missing triggers and overlapping neighbours.
6. Run `Set-SkillVersion.ps1`, `Test-SkillLibrary.ps1`, markdownlint and, with approval,
   `Skills.Tests.ps1`, then re-measure and report the before and after figures. Run markdownlint
   in-process through the `tooling-pre-commit` skill's
   `& Invoke-PreCommit.ps1 -HookId markdownlint -Files @(...)`, which falls back to Docker;
   `pwsh -File` passes a comma list as one path, and `npx` on Windows mangles arguments.
