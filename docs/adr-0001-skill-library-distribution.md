# ADR 0001: Skill Library Distribution

**Status:** Accepted.
**Date:** 2026-10-31.
**Scope:** Independent versioning of each skill in `.github/skills/`, packaging as Spec Kit
extensions in GitHub Releases, and installation through one bootstrap extension.

## Context and Problem

Skills are consumed natively by adding this repository to a workspace or linking its folders into the
user profile. That route stays supported. Consumers who want selected skills, at exact versions, in
a Spec Kit repository need versioned packages and a way to install a skill with the skills it needs.

The first implementation (tags `1.5.0` to `1.5.3`) grew to roughly 10,000 lines of PowerShell,
Python and tests, plus Spec Kit dogfooding artifacts. Most of it defended against hostile writers,
crashes and concurrency that a single-owner Markdown packager does not face, and it reimplemented
installation that Spec Kit already provides. It never published a release. Git history keeps it.

## Decision

1. **One sidecar per skill.** Every skill folder has `skill.metadata.yaml` with `version`, optional
   `facets`, `required` skills pinned to exact versions, `related` skills with a reason, and
   `externalFiles` outside the folder. The component ID is the folder name.
2. **PowerShell and `yq` only.** Repository tooling uses PowerShell 7.4+, Git and `yq` v4. No Python.
3. **One extension per skill.** A build packages the skill folder, its external files and `LICENSE`
   into a deterministic Spec Kit extension ZIP. Required skills are separate extensions, not bundled.
4. **Versions are checked, not inferred.** A pull request fails when a skill changed since its last
   `<id>/X.Y.Z` tag without a version bump, or when a required pin is stale. `Set-SkillVersion`
   bumps a skill and cascades pin updates and patch bumps to skills that require it.
5. **Releases on merge.** On `main`, each component without a matching tag is built and published
   as GitHub Release `<id>/X.Y.Z`. A rolling `skills-catalog` release holds one Spec Kit catalog
   with every published version. GitHub Pages may replace the rolling release after the demo.
6. **One bootstrap command.** The `skill` extension provides `/speckit-skill-library`. Its
   PowerShell helper wraps the `specify` CLI: it searches the catalog, resolves the required
   closure, offers related skills for explicit selection, installs through `specify extension add`
   and lists installed guidance for loading. Spec Kit verifies archive digests.

## Options Considered

| Option | Assessment |
| --- | --- |
| Keep the first implementation | Rejected: too large to maintain or demo, and it never published. |
| Bundle required skills into each ZIP | Rejected: duplicates content; the bootstrap resolves the closure instead. |
| Rely on Spec Kit dependency resolution | Unavailable: Spec Kit 1.2.3 only checks `requires.speckit_version`. |
| Native consumption only | Kept as the default route, but it offers no versioned selection. |

## Consequences

- Consumers need the `specify` CLI, PowerShell 7.4+ and network access to GitHub Releases.
- Installing a skill through `specify extension add` directly skips its required skills; use the
  bootstrap command.
- Related skills install at their current catalog version; only required edges pin versions.
- Renaming a skill folder creates a new component ID. Published releases and tags are never moved.
- Digests prove integrity, not authorship. Signing, upgrades of installed skills and uninstall
  orchestration are out of scope until needed.

## Validation and Delivery

- [x] Accept this minimal decision and delete the previous design record's history narrative.
- [ ] Delete the first implementation, its tests, delivery workflows and Spec Kit dogfooding folders.
- [ ] Add a sidecar to every skill and validate all sidecars with `yq` and PowerShell.
- [ ] Build a deterministic extension ZIP per skill with external files and `LICENSE`.
- [ ] Fail pull requests on unbumped changes or stale required pins; bump with cascade.
- [ ] Build the `skill` bootstrap extension with `/speckit-skill-library`.
- [ ] Publish missing `<id>/X.Y.Z` releases and the rolling catalog from `main`.
- [ ] Cover validation, build, version checks, bump cascade and plan resolution with Pester.
- [ ] Rewrite the `skill-library` skill and README for the new workflow.
- [ ] Install and load skills with related selection in a fresh `specify init --script ps` consumer.
- [ ] Publish a real follow-on version of one skill and its required dependents.

## Open Questions

- Should the catalog move to GitHub Pages after the demo?
- Do upgrades or removal of installed skills need bootstrap support, or is `specify extension` enough?
