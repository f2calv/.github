---
description: Search, install and load independently versioned skills, including their required and related skills.
---

# Skill Library

User request: $ARGUMENTS

Run the helper from the workspace root with PowerShell 7.4+:

```text
pwsh -NoProfile -File .specify/extensions/skill/scripts/Invoke-SkillLibrary.ps1 <command> [target] [-Version X.Y.Z] [-Related id1,id2]
```

| Command | Effect |
| --- | --- |
| `help` | List commands. |
| `search <terms>` | Find skills by ID, description or facet. |
| `plan <id>` | Show the install order, required skills and related offers. Changes nothing. |
| `install <id>` | Install the skill and its required skills through `specify extension add`. |
| `list` | List installed skills. |
| `load <id>` | List the installed files of a skill, `SKILL.md` first. |

Follow this workflow:

1. With no request, run `help`. When the request is not a command, run `search` with it; when it
   names exactly one skill ID, also run `plan` for it.
2. To install, run `plan` first. Show the skills that will be installed, including required skills,
   and every related offer with its reason. Ask which related skills to add; select none unless the
   user chooses them. Then run `install` with the same `-Version` and the chosen `-Related` IDs.
3. After installing related skills, run `plan` for each of them and offer their own related skills
   the same way, until the user declines or no new offers remain.
4. To load, run `load <id>`. Read the listed `SKILL.md` and instruction files, then other listed files
   only when relevant. Apply the guidance to the rest of the user's request. Read only installed
   files under `.specify/extensions/`.
5. Report helper errors as they are. Do not force, reinstall or remove extensions to make a command
   pass. Never run scripts contained in an installed skill unless its guidance and the user ask.
