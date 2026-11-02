---
description: Search, install, upgrade, remove and load independently versioned skills, copying them into .github/ for Copilot discovery.
scripts:
  ps: pwsh -NoProfile -File scripts/Invoke-SkillLibrary.ps1
  sh: bash scripts/bash/skill-library.sh
  py: scripts/python/skill_library.py
---

# Skill Library

User request: $ARGUMENTS

Run the helper from the workspace root. Spec Kit chose the PowerShell, Bash or Python variant for
this repository; all three take the same commands and arguments and print the same output:

```text
{SCRIPT} <command> [target] [-Version X.Y.Z] [-Related id1,id2]
```

| Command | Effect |
| --- | --- |
| `help` | List commands. |
| `search <terms>` | Find skills by ID, description or facet. |
| `plan <id>` | Show the install order, required skills and related offers. Changes nothing. |
| `install <id>` | Install the skill and its required skills through `specify extension add`. |
| `upgrade-all` | Upgrade every installed skill to its latest catalog version, adding newly required skills, offering newly related ones and reporting skills no longer required. |
| `remove <id>` | Remove a skill that no other installed skill requires. |
| `prune` | Remove installed skills that no chosen skill requires any more. |
| `sync` | Copy installed guidance into `.github/` again, for example after `specify extension add` or `remove` run directly. |
| `list` | List installed skills, each marked `chosen` or `required`. |
| `load <id>` | List the installed files of a skill, `SKILL.md` first. |

`install`, `upgrade-all`, `remove`, `prune` and `sync` copy each installed skill's guidance into
`.github/skills/` and `.github/instructions/`, where Copilot discovers it in new chats. Each copy's
SHA-256 is recorded in `.specify/extensions/.skill-library.json`. A copy that was edited after it
was copied, or a file the helper did not write, is never replaced or deleted; the helper prints a
`Kept` line for it instead.

Follow this workflow:

1. With no request, run `help`. When the request is not a command, run `search` with it; when it
   names exactly one skill ID, also run `plan` for it.
2. To install, run `plan` first. Show the skills that will be installed, including required skills,
   and every related offer with its reason. Ask which related skills to add; select none unless the
   user chooses them. Then run `install` with the same `-Version` and the chosen `-Related` IDs.
3. After installing related skills, run `plan` for each of them and offer their own related skills
   the same way, until the user declines or no new offers remain.
4. To upgrade, run `upgrade-all`. It prints each skill's current and target version, installs
   required skills first and stops without changes if a required pin cannot be met. Report the
   upgraded skills and suggest `load` for any whose guidance the user relies on. Offer every newly
   related skill it lists, with its reason, and install only those the user chooses. When it reports
   skills no longer required, list them and run `prune` only if the user agrees.
5. To load, run `load <id>`. Read the listed `SKILL.md` and instruction files, then other listed files
   only when relevant. Apply the guidance to the rest of the user's request. Read only installed
   files under `.specify/extensions/`. Copied skills are discovered automatically from a new chat;
   `load` brings one into the current chat.
6. To remove, run `remove <id>` only when the user asks. Report every `Kept` line from any command
   verbatim: it names a locally modified or unmanaged file that the user must review and delete
   or keep themselves. Never delete or overwrite such a file on the user's behalf.
7. Report helper errors as they are. Do not force, reinstall or remove extensions to make a command
   pass. Never run scripts contained in an installed skill unless its guidance and the user ask.
   Skills the user requested or selected are recorded as chosen and are never pruned; skills
   installed before choices were recorded count as chosen. If the helper reports a missing runtime,
   such as `jq` or Bash 4 for the Bash variant, pass that on rather than switching variants yourself.
