# How the Repository Works

This repository is the single source of truth for shared Copilot instructions and skills. It serves
them through Copilot workspace guidance, independently versioned Spec Kit extensions and Agent
Plugins. This document explains the structure, versioning, packaging and installation behind
the three supported routes.

## Repository Layout

| Path | Contents |
| --- | --- |
| `.github/instructions/` | `*.instructions.md` files; each `applyTo` glob decides which files it governs |
| `.github/skills/<id>/` | One skill per folder: `SKILL.md`, optional scripts, references and examples, plus `skill.metadata.yaml` |
| `.github/skills/skill-library/` | The tooling that validates, versions, builds and publishes every skill; see [Skill Library Tooling](architecture/skill-library-tooling.md) for its components |
| `src/skill-library-extension/` | The `skill` bootstrap extension that provides `/speckit-skill-library` |
| `.github/copilot-instructions.md` | Rules for authoring this repository itself, not part of the shared set |
| `docs/` | This documentation and the [distribution ADR](adr-0001-skill-library-distribution.md) |

## Dependency Graph

A skill's `skill.metadata.yaml` sidecar declares what it needs. **Required** skills are pinned to an
exact version and always installed with it. **Related** skills are offered with a reason and
installed only when chosen. **External files**, typically instructions the skill links to, are
packaged inside the skill's extension. **Facets** are search tags. The
[sidecar reference](skill-metadata.md) explains every field.

```mermaid
graph LR
    adr([docs-adr])
    privacy([repository-privacy])
    issues([github-issues-and-pull-requests])
    md[markdown.instructions.md]
    mermaid[markdown.mermaid.instructions.md]

    adr -- "required, exact sidecar version" --> privacy
    adr -. "related, offered" .-> issues
    adr -- "external file, packaged" --> md
    adr -- "external file, packaged" --> mermaid

    classDef skill fill:#dbeafe,stroke:#1d4ed8,color:#000
    classDef file fill:#f3f4f6,stroke:#6b7280,color:#000
    class adr,privacy,issues skill
    class md,mermaid file
```

Required edges must not form a cycle; the validation check rejects one.

## Versioning

Every skill has its own semantic version in its sidecar. A release is the Git tag `<id>/X.Y.Z`.

| Change | Bump |
| --- | --- |
| Breaking guidance change | `major` |
| New capability | `minor` |
| Fix or clarification | `patch` (default) |
| A required skill was bumped | `patch` for each released dependent, with its pin updated |

Rules enforced on every pull request by `Test-SkillLibrary.ps1`:

- A skill, or any of its external files, that changed since its last tag must be bumped.
- A version may be at most one step past its last tag: `1.0.0` may become `1.0.1`, `1.1.0` or
  `2.0.0`, never `1.0.3`. However often a skill changes on a branch, it is bumped once.
- Every required pin must equal the required skill's current version.
- A skill that has never been released keeps its authored version; its first release uses it.

`Set-SkillVersion.ps1` applies these rules. It always bumps from the last released tag, so running it
repeatedly during a long session never stacks bumps, and it cascades pin updates and patch bumps to
dependents.

## Skill Version Lifecycle

A skill's version moves between these states as it is edited, bumped and published.

```mermaid
stateDiagram-v2
    [*] --> Unreleased: skill folder and sidecar created
    Unreleased --> Released: merged to main, Publish-SkillRelease.ps1 creates id/X.Y.Z
    Released --> Changed: skill or external file edited
    Changed --> Changed: Test-SkillLibrary.ps1 fails the pull request
    Changed --> Bumped: Set-SkillVersion.ps1, one step from the last tag
    Released --> Bumped: required skill bumped, pin and patch cascade
    Bumped --> Released: merged to main, release published
```

## Deployment Flow

Releases are published by jobs in the [CI workflow](../.github/workflows/ci.yml). Every pull request
and default-branch push runs the checks; only `main` publishes.

```mermaid
flowchart LR
    classDef ci fill:#dcfce7,stroke:#15803d,color:#000
    classDef store fill:#e5e7eb,stroke:#4b5563,color:#000

    edit([Edit a skill]) --> bump[Set-SkillVersion.ps1<br/>bump once from last tag]
    bump --> lint[lint]:::ci
    bump --> test[skills-library-tests and Windows/macOS platform tests<br/>then test aggregate]:::ci
    bump --> versions[skill-versions<br/>Test-SkillLibrary.ps1]:::ci
    bump --> examples[dotnet-examples]:::ci
    lint --> main{On main?}
    test --> main
    versions --> main
    examples --> main
    main -- no --> done([Checks only])
    main -- yes --> releases[skill-releases<br/>Publish-SkillRelease.ps1<br/>ZIP per untagged version]:::ci
    releases --> release[(GitHub Release<br/>id/X.Y.Z)]:::store
    releases -->|"site generated"| catalog[skill-catalog<br/>deploy Pages]:::ci
    catalog --> pages[(GitHub Pages<br/>catalog.json and index.html)]:::store
    releases --> repository[Repository release after all validation and catalog results]:::ci
    catalog --> repository
```

On `main`, CI publishes each component whose version has no tag yet. Publishing the release creates
the tag on the merge commit. CI then regenerates `catalog.json`, listing every published version with
its download URL and SHA-256 digest, plus a browsable `index.html`, and deploys both to
[GitHub Pages](https://f2calv.github.io/.github/). The ZIPs stay on the releases. Published
releases are never changed or moved.

## Packaging

Each skill becomes one Spec Kit extension ZIP. Required skills are separate extensions, not bundled.

```mermaid
graph TD
    zip([docs-adr-X.Y.Z.zip])
    manifest[extension.yml<br/>id, version, description]
    res[resources/]
    skill[.github/skills/docs-adr/...]
    ext[.github/instructions/markdown*.instructions.md]
    lic[LICENSE]

    zip --> manifest
    zip --> res
    res --> skill
    res --> ext
    res --> lic
```

Files keep their repository paths under `resources/`, so relative links between a skill and its
instructions still resolve after installation. Only committed files are packaged, and rebuilding the
same commit produces byte-identical archives.

### Agent Plugins

The same release also carries the skill as an [Agent Plugins](https://agent-plugins.org/) package,
built from the same commit and version. The decision is recorded in
[ADR 0002](adr-0002-agent-plugins-packaging.md).

```mermaid
graph TD
    zip([docs-adr-X.Y.Z-plugin.zip])
    manifest[plugin.json<br/>name, version, keywords, extensions]
    skill[skills/docs-adr/...<br/>portable frontmatter]
    ext[instructions/markdown*.instructions.md]
    lic[LICENSE]

    zip --> manifest
    zip --> skill
    zip --> ext
    zip --> lic
```

- External files drop their `.github/` prefix, so the skill's `../../instructions/...` links resolve
  inside the plugin root, as the specification requires.
- VS Code-only frontmatter fields move into `metadata` in the package, so strict clients accept the
  skill. The source files are unchanged.
- Required and related skills are recorded under the `io.github.f2calv.skill-library` extension
  namespace. Agent Plugins has no dependency mechanism, so a client installs only the one skill.
- Instructions are inert reference files read when the skill follows a link; `applyTo` matching
  happens only in the Copilot and Spec Kit routes.
- The `speckit-*` skills that `specify init` generates belong to Spec Kit and are never validated,
  versioned or packaged here.

## Installation Flow

```mermaid
sequenceDiagram
    actor User
    participant Chat as Copilot Chat
    participant Cmd as /speckit-skill-library
    participant Catalog as GitHub Pages catalog
    participant Specify as specify CLI
    participant Releases as GitHub Releases

    User->>Chat: /speckit-skill-library install docs-adr
    Chat->>Cmd: run install docs-adr
    Cmd->>Catalog: fetch catalog.json
    Cmd->>Cmd: resolve required closure<br/>exact sidecar and catalog versions
    Cmd->>User: offer related github-issues-and-pull-requests
    User->>Cmd: accept or decline
    loop each skill in dependency order
        Cmd->>Specify: specify extension add (skill id)
        Specify->>Releases: download ZIP
        Specify->>Specify: verify SHA-256 from catalog
    end
    Cmd->>Cmd: copy guidance into .github/<br/>and record each copy's SHA-256
    Cmd->>User: report copies and any kept files
```

`/speckit-skill-library upgrade-all` follows the same path for every installed skill whose catalog
version is newer, replacing it with `specify extension add --force` and installing newly required
skills. It then offers newly related skills and reports skills no chosen skill requires, which
`/speckit-skill-library prune` removes with `specify extension remove`; `remove <skill>` removes one
chosen skill that nothing else requires. The helper records chosen versus required skills, and each
copied file's SHA-256, in `.specify/extensions/.skill-library.json`.

### Copied Guidance

Spec Kit extensions cannot provide skills, so Copilot never discovers a skill left under
`.specify/extensions/`. After each change the helper mirrors every enabled skill's
`resources/.github/` into the workspace `.github/` and reconciles the copies against their records:

```mermaid
flowchart TD
    start([Copy or delete a file]) --> exists{Workspace file exists?}
    exists -- No --> act[Copy, or nothing to delete]
    exists -- Yes --> rec{Recorded copy?}
    rec -- No --> keep1[Keep: not written by the helper]
    rec -- Yes --> match{Bytes match recorded SHA-256?}
    match -- Yes --> act2[Replace or delete, update the record]
    match -- No --> keep2[Keep: modified locally, report skill, version and date]
```

When two skills ship the same instruction file, the copy from the first skill by ID is used and a
differing copy is reported.

## Routes Compared

| Aspect | Copilot route | Spec Kit route | Agent Plugins route |
| --- | --- | --- | --- |
| Setup | Add to workspace or link into `~/.copilot` | `specify extension add skill`, then `/speckit-skill-library install` | Download and extract `<skill>-<version>-plugin.zip`, then load it in the client |
| Version | Whatever the clone has checked out | Exact published versions | Exact published versions |
| Selection | Every instruction and skill | Chosen skills plus their required closure | One skill per plugin; required plugins installed by hand |
| Instructions | Applied automatically by `applyTo` | Copied into `.github/instructions/` and applied by `applyTo` | Linked files packaged as reference |
| Updates | `git pull` | `/speckit-skill-library upgrade-all` | Replace with the newer package |
| Prerequisites | VS Code with Copilot | Specify CLI, access to GitHub Pages and Releases, and PowerShell 7.4+, Bash 4+ with `jq`, or Python for the chosen helper variant | An Agent Plugins client and access to GitHub Releases |
