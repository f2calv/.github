# Copilot Instructions

This repository is the single source of truth for every reusable Copilot customization used across `f2calv` repositories — instruction files and agent skills.

Individual repositories no longer carry a `.github/instructions/` folder. They keep only their own `.github/copilot-instructions.md`, which points here and holds that repository's specific rules.

## Setup

The shared files live under `.github/instructions/` and `.github/skills/`, which VS Code reads for
any folder open in a workspace. As the [README](../README.md) describes, keep this repository in the
workspace for editing and link its folders into `~/.copilot/` so agent sessions in every other
repository load them; agent sessions read workspace customizations only from the folder they start
in. VS Code 1.144.0 fixed a bug that loaded the linked files twice.

User-profile customizations take priority over repository instructions, so a repository that
overrides a central rule must say so explicitly in its own `copilot-instructions.md`. Because the
files are not copied into other repositories, a change here never triggers their CI.

## Layout

| Path                              | Purpose                                                        |
| --------------------------------- | -------------------------------------------------------------- |
| `.github/instructions/`           | Canonical `*.instructions.md` files                            |
| `.github/skills/`                 | Reusable agent skills                                          |
| `.scripts/`                       | Repository management, baseline and privacy tooling            |
| `.github/copilot-instructions.md` | This repository's own instructions, not part of the shared set |

## Authoring Rules

- These files are public. They must contain no personally identifiable information, no credentials, no private repository names, and no project-specific examples. Write every rule so it reads sensibly in any repository.
- Keep the author's own circumstances out of the rules: their devices, employer or device-management policies, workstation layout, drives and accounts. When such a situation teaches something general, state it as a condition any reader could meet ("if a phone is enrolled in device management…") rather than as the default case.
- Before committing, scan these files with the [repository privacy skill](skills/repository-privacy/SKILL.md#shared-guidance-files)'s `Find-SpecificReferences.ps1`: resolve every error, and reframe or deliberately keep each review item.
- Name repositories, packages and types generically (`owner/example`, "the shared library", "the domain exception base"). The author's public repositories and packages, such as `CasCap.Common`, may be named, but always as example libraries ("for example, the public `CasCap.Common.Caching` package; other libraries may serve"), never as the required choice, and keep the rule itself library-neutral. Name private repositories nowhere. A longer worked case goes in a section headed as a real-world example.
- Scoped `*.instructions.md` files carry YAML frontmatter with a `description` and an `applyTo`
  glob. Skills instead require `name` and a discovery-focused `description`; `applyTo` does not
  invoke a skill. Ordinary supporting documentation has no customization frontmatter.
- Add no attribution or "brought to you by" footer to a file or a `description`; it is noise in every agent's context.
- Code in skills, examples and references follows the same instructions it would in a real
  repository, for example strongly-typed options instead of configuration key strings. Label a
  deliberate anti-pattern as such next to the snippet.
- `applyTo` is matched relative to the workspace root. Prefer portable patterns such as `**/*.cs`. Avoid patterns anchored to one repository's folder layout.
- Keep always-on files to invariants, scope `applyTo` to governed paths, and give every skill an
  unquoted `name`, a `description` of at most 600 characters with a `Use when`/`Use for` trigger, no
  default-valued fields and a `SKILL.md` under 16 KB. The
  [authoring reference](skills/skill-library/references/authoring-and-context-budget.md) explains
  the cost model and audit; `.scripts/tests/Skills.Tests.ps1` enforces the skill rules.
- One topic per file, named `<topic>.instructions.md`. Keep rules short and self-contained, and say why a rule exists where the reason is not obvious.
- Prefer amending an existing file over adding a near-duplicate one.
- Every `SKILL.md` has a `## Maintaining This Skill` section listing that skill's own drift triggers:
  the versions, tool behaviours, external APIs or steps most likely to go stale. Keep the general
  feedback-loop rule in `workflow.instructions.md`, not repeated per skill.
  `.scripts/tests/Skills.Tests.ps1` enforces the section in CI.
- Every skill folder has a `skill.metadata.yaml` sidecar and an independent version. After adding or
  changing a skill, follow the [skill library workflow](skills/skill-library/SKILL.md#validate-and-bump):
  fetch tags, scaffold missing sidecars, bump changed skills and run `Test-SkillLibrary.ps1` before
  committing. CI rejects missing sidecars and unbumped changes.
- Every PowerShell script has a matching `<Name>.Tests.ps1`, except `Invoke-Tests.ps1` runners and
  `*.Common.ps1` helpers tested through their callers.
- For targeted structural checks, pass `SkillName` through `New-PesterContainer -Data` to that
  suite. Its data-driven Describe names are not expanded when Pester applies name filters;
  always check the executed test count instead of accepting a zero-test success.
  Import the repository-pinned Pester version before creating the container; auto-loading another
  installed version can conflict with the suite's `#Requires` and fail discovery.

## What Stays in Each Repository

A repository keeps a single `.github/copilot-instructions.md` containing:

1. A pointer to this repository for the shared instructions and skills.
2. Rules genuinely specific to that repository — its purpose, architecture, domain terminology, and any deliberate deviation from a central rule.

Every newly bootstrapped repository starts that file with this exact preamble, kept byte-identical
through the final sentence so the shared boundary does not drift between repositories:

```markdown
# Copilot Instructions

## Shared Instructions

Shared Copilot instructions, skills and prompts are maintained centrally in the [.github](https://github.com/f2calv/.github) repository, under `.github/instructions/`, `.github/skills/` and `.github/prompts/`. They are deliberately not copied into this repository, so a change there takes effect everywhere without a pull request here.

To load them, clone that repository and either add it to this VS Code workspace, or link its folders into `~/.copilot/`. Its README explains both.

If those shared files are not visible, stop and tell the user rather than guessing the conventions — this repository depends on them.

Everything below is specific to this repository.
```

It must not contain a `.github/instructions/` folder or a copy of any centrally maintained file.
