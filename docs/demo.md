# End-to-End Demos

Scripted walkthroughs for presenting the repository, from everyday Copilot use to publishing and
upgrading versioned skills. Each demo lists its setup, the exact steps and what the audience should
see. Run them in a disposable demo repository, never in a real project.

| Demo | Shows | Needs |
| --- | --- | --- |
| [1. Instructions apply automatically](#1-instructions-apply-automatically) | Copilot following shared conventions with no prompt engineering | VS Code with Copilot |
| [2. Invoke a skill](#2-invoke-a-skill) | A task-specific workflow with safety gates | VS Code with Copilot |
| [3. Version a skill change](#3-version-a-skill-change) | One bump per branch, the pin cascade and the pull request gate | PowerShell 7.4+, Git, `yq` v4 |
| [4. Package a skill](#4-package-a-skill) | Deterministic Spec Kit extension ZIPs | As demo 3 |
| [5. Install from the catalog](#5-install-from-the-catalog) | Required and related skills installed through Spec Kit | Specify CLI, PowerShell 7.4+ |
| [6. Upgrade installed skills](#6-upgrade-installed-skills) | `upgrade-all` moving every skill to its latest version | As demo 5 |
| [7. Fully local catalog](#7-fully-local-catalog) | The whole pipeline offline, before anything is published | Demos 4 and 5 prerequisites, Python 3 |

## 1. Instructions Apply Automatically

**Setup.** Add this repository to the workspace beside an empty demo repository, as described in the
[README](../README.md#add-to-a-workspace).

1. In the demo repository, create `src/Example/Program.cs`.
2. Ask Copilot: *Read the gRPC server address from configuration and register a client for it.*
3. Point out what the shared [C#](../.github/instructions/dotnet.csharp.instructions.md) and
   [configuration](../.github/instructions/dotnet.configuration.instructions.md) instructions
   produce: an options record with a `ConfigurationSectionName` constant,
   `AddOptionsWithValidateOnStart` and no `Configuration["..."]` key strings.
4. Open **Chat: Open Customizations** to show which instruction files matched `*.cs`.

**Expected.** The generated code follows the conventions without the prompt mentioning them.

## 2. Invoke a Skill

1. In the demo repository, run `/docs-adr draft a decision on caching product prices in Redis`.
2. Show the local ADR under `docs/`, its options table, consequences and validation checklist.
3. Ask a follow-up requirement and show the ADR updated in place rather than appended.

**Expected.** The skill loads its required [repository privacy](../.github/skills/repository-privacy/SKILL.md)
rules and writes no GitHub issue unless asked.

## 3. Version a Skill Change

Run in a scratch branch of this repository.

```powershell
git switch -c demo/skill-bump
git fetch --tags
Add-Content .github/skills/repository-privacy/SKILL.md "`n<!-- demo change -->"
./.github/skills/skill-library/scripts/Test-SkillLibrary.ps1
./.github/skills/skill-library/scripts/Set-SkillVersion.ps1 -Id repository-privacy
./.github/skills/skill-library/scripts/Set-SkillVersion.ps1 -Id repository-privacy
git diff -- '*.yaml'
./.github/skills/skill-library/scripts/Test-SkillLibrary.ps1
```

**Expected.**

1. The first check fails: `repository-privacy: changed since repository-privacy/1.0.0`.
2. The first bump moves `repository-privacy` to the next patch and cascades to `docs-adr`, which
   requires it: new pin plus its own patch bump.
3. The second bump changes nothing; bumps always start from the last released tag.
4. The diff shows only those two sidecars; `terraform-infrastructure`, which lists the skill as
   related only, is untouched.
5. The final check passes.

To show the gate rejecting a version gap, hand-edit the `repository-privacy` version two patches
ahead and rerun `Test-SkillLibrary.ps1`. Discard the branch afterwards.

## 4. Package a Skill

```powershell
./.github/skills/skill-library/scripts/Build-SkillExtension.ps1 -Id docs-adr -OutputDirectory ./artifacts
./.github/skills/skill-library/scripts/Build-SkillExtension.ps1 -Id docs-adr -OutputDirectory ./artifacts2
Get-FileHash ./artifacts/*.zip, ./artifacts2/*.zip
[IO.Compression.ZipFile]::OpenRead((Resolve-Path ./artifacts/*.zip)).Entries.FullName
```

**Expected.** Identical hashes for both builds, and entries for `extension.yml`, the skill folder,
the Markdown instructions it links to and `LICENSE`, all under `resources/`. Builds refuse
uncommitted changes, so run this on a clean tree.

## 5. Install from the Catalog

Open <https://f2calv.github.io/.github/> to show the published catalog page, then in a new empty
demo repository:

```powershell
specify init --here --integration copilot --script ps
$env:SPECKIT_CATALOG_URL = 'https://f2calv.github.io/.github/catalog.json'
specify extension add skill
Remove-Item Env:SPECKIT_CATALOG_URL
```

In Copilot Chat:

```text
/speckit-skill-library search architecture
/speckit-skill-library install docs-adr
/speckit-skill-library list
/speckit-skill-library load docs-adr
```

**Expected.** `install` plans `repository-privacy` before `docs-adr`, offers
`github-issues-and-pull-requests` with its reason and installs only what you accept. `load` lists
`SKILL.md` first. Finish by asking a question that uses the loaded skill.

## 6. Upgrade Installed Skills

Continue in the demo 5 repository. Install an older version first so there is something to upgrade:

```text
/speckit-skill-library install skill-library -Version 1.0.0
/speckit-skill-library upgrade-all
/speckit-skill-library list
```

**Expected.** `upgrade-all` prints each installed skill with `current` or `upgrade from X`, replaces
only the outdated ones, required skills first, and `list` shows the latest versions.

## 7. Fully Local Catalog

Demonstrates the complete flow without GitHub, for example before a branch merges.

```powershell
./.github/skills/skill-library/scripts/Build-SkillExtension.ps1 -OutputDirectory ./artifacts -CatalogBaseUrl http://localhost:8765/
python3 -m http.server 8765 --directory ./artifacts
```

In a second terminal, in a new demo repository, set both catalog variables before running demo 5:

```powershell
$env:SPECKIT_CATALOG_URL = 'http://localhost:8765/catalog.json'
$env:SKILL_LIBRARY_CATALOG_URL = 'http://localhost:8765/catalog.json'
```

**Expected.** The same install experience as demo 5, served from the working tree's committed state.
The local catalog lists only current versions, so `upgrade-all` has nothing to upgrade here.
