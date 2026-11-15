---
name: docs-mkdocs
description: 'Create, extend and audit MkDocs documentation on GitHub Pages for public repositories. Use when adding mkdocs.yml or docs.yml, publishing existing Markdown, enabling Pages, or preserving catalogs and Helm chart feeds alongside documentation. Repository settings belong to github-repository-baseline; shared CI belongs to github-actions-workflows.'
argument-hint: 'mode={create|update|audit} [repository=path]'
---

# MkDocs Documentation

Publish browsable, searchable documentation from canonical Markdown without breaking other
consumers of the repository's GitHub Pages site.

## Boundaries

* Scope automatic publication to public repositories. Private repository visibility does not prove
  a Pages site is private; never publish private material or change visibility as a workaround.
* Obtain approval before changing remote Pages settings, dispatching publication, or creating and
  merging a pull request. A local documentation build does not authorize any of those operations.
* Use the [repository baseline](../github-repository-baseline/SKILL.md) for settings ownership and
  the [Actions workflow skill](../github-actions-workflows/SKILL.md) for shared CI. If the baseline
  does not support Pages, report that gap rather than pretending its audit covers the setting.
* Keep Pages opt-in per repository; an omitted policy setting leaves existing hosting unmanaged.
  Do not enable documentation across an account merely because its repositories are public.
* The [README skill](../docs-readme/SKILL.md) owns README content. Render existing instructions,
  skills, references and guides without keeping a second hand-maintained copy of them.

## Workflow

### 1. Inventory Hosting and Consumers

Read the repository's instructions and inspect its Markdown, documentation dependencies, Pages
settings, deployment history and every workflow that can publish to Pages or its source branch.
Read Pages settings with `gh api repos/<owner>/<repository>/pages`; do not infer them from the
absence of a MkDocs configuration or a branch named `gh-pages`.

Record the current publishing source, custom domain, site root and public URL contracts. Ask about
planned consumers too: a repository without a current chart feed may reserve Pages for one later.
Do not treat that possibility as permission to create a feed or claim that one already exists.

### 2. Agree the Shared-Site Contract

GitHub Pages is repository-wide publishing space, not a separate destination for each workflow.
A Pages artifact deployment replaces the published site; it does not merge its files with the
previous deployment. A concurrency group alone cannot prevent one complete payload replacing
another publisher's content.

* Inventory human and machine consumers, including a skill `catalog.json`, Helm `index.yaml`,
  chart archives, download links, existing landing pages and `CNAME` where applicable. Preserve
  their URLs, schemas, generation authority and update timing unless a migration is approved.
* Choose explicit output ownership and reserve paths for agreed future consumers. If the root
  already belongs to a catalog or chart feed, place documentation under an agreed subpath rather
  than replacing the root landing page or moving a machine index to make room.
* Keep one coordinated Pages publication containing the complete payload. Independent builders
  may produce documentation, catalogs and charts, but assemble their reviewed outputs into one
  artifact, reject path collisions and deploy only after every required producer succeeds.
  Do not add a competing `mkdocs gh-deploy`, force-push a publishing branch, or switch the Pages
  source from branch publishing to Actions without an explicit migration.
* Build from the authoritative sources or approved immutable artifacts, not a scrape of the live
  site that can silently preserve stale files. A documentation refresh must not create releases,
  publish unreleased skills into a catalog, regenerate a feed from an incomplete chart set, or
  change existing package-release gates.
* Preserve a chart feed's archive URLs and complete version history as well as `index.yaml`.
  Moving an index without checking its relative archive links can break `helm repo update` or
  chart downloads. The [Helm skill](../kubernetes-helm/SKILL.md) owns feed generation and packaging.
* Before changing deployment ownership, identify other sessions, workflows and clients relying
  on the current publisher. Agree the hand-off and rollback; never let parallel publishers race
  on the assumption that they touch different files.

### 3. Configure the Documentation Build

Reuse the repository's Python tooling and pin a compatible MkDocs, theme and plugin set with a
reproducible dependency lock. Keep documentation dependencies separate from application runtime
dependencies. Verify current upstream compatibility rather than copying obsolete version pins.

Choose a small navigation structure around the repository's audiences. Include search, readable
code blocks and Mermaid rendering where existing documents use diagrams. Set the correct project
site URL and base path; a project site is not served at the account site's root.

Use the existing public Markdown as the source of truth. When generating pages or navigation,
enumerate Git-tracked, reviewed public inputs, not every file in the local checkout. Exclude
ignored local guidance, credentials, generated build outputs, fixtures and private configuration.
Preserve or deliberately transform relative links and anchors. Link non-document sources such as
scripts and templates to their repository locations instead of generating broken site links.
Do not rewrite canonical instructions solely to satisfy a site renderer.

### 4. Wire Validation and Publication

Prefer an existing shared workflow; otherwise follow the Actions skill's shared-workflow authoring
procedure before duplicating cross-repository build and deployment logic. A repository's
`.github/workflows/docs.yml` should be a thin caller where a suitable shared workflow exists.

Ordinary repositories need only a MkDocs configuration, canonical `docs/` sources and locked
documentation dependencies. Keep staging optional and repository-specific, not a script every
consumer must copy. Use the shared build artifact with official Pages actions in a caller-owned
deployment; wait for a new workflow to ship before referencing its major alias. Preserve generated
dot-prefixed pages during artifact transfer, without broadening uploads to the source checkout.
The official Pages artifact action always excludes `.git` and `.github`, even with hidden-file
inclusion enabled: map canonical guidance to a normal generated output path and verify the actual
packaging contract, not only the intermediate build artifact.
For a shared site, a guarded copy into a reserved subpath is sufficient when it preserves protected
indexes; do not add another script or publisher merely to copy files.

* Build documentation on pull requests, including fork and dependency-bot pull requests, with
  read-only access and no secrets. Do not use `pull_request_target` to execute incoming content.
* Deploy only trusted default-branch pushes after merge and any separately approved manual run.
  Require both the expected event and ref; a pull request must never receive deploy permissions.
* Grant the build only `contents: read`. Grant the protected deployment job only the required
  `pages: write` and `id-token: write` permissions and use the `github-pages` environment.
* For Actions publishing, use the official Pages configuration, artifact and deployment actions.
  Configure settings only after checking existing source ownership and the shared-site contract.
* Serialize complete-site deployments and prevent an older build publishing over a newer site.
  Do not cancel an in-progress deployment blindly; follow the existing deployment policy.
* Documentation-only merges must refresh documentation without forcing a package release. Keep
  the catalog or feed's existing merge-time generation and publication contract intact.
* When documentation is a required gate, ensure the check reports on every pull request. Update
  baseline-required check names only after verifying the actual emitted job name.

### 5. Validate a Pilot Before Generalizing

With build approval, use the same locked environment locally and in CI:

```shell
mkdocs build --strict --clean
```

Check navigation, search, Mermaid, assets, source links, anchors and project-site base paths.
Serve the built static files locally and inspect representative pages; a successful Markdown
conversion alone does not establish a usable site. Ask separately before running test suites.

Use a fresh dedicated output for publication checks. MkDocs `--clean` retains dot-prefixed entries,
so an old local hidden directory can survive a build and enter an artifact unexpectedly.

For a shared site, verify the final artifact contains every protected index and required asset,
not only the MkDocs output. Compare machine indexes against their authoritative generated outputs
and validate representative catalog entries or chart downloads. Prove that documentation-only and
catalog/feed-only updates each preserve the other output. Test that overlapping paths fail rather
than silently winning by copy order. Repeat relevant checks after any publisher hand-off.

Before approved publication, run the [privacy checks](../repository-privacy/SKILL.md), lint the
workflow through the repository's configured hooks, and validate the pull-request build without
deploying. After an approved deployment, verify the live documentation and preserved machine URLs.
Report local build evidence separately from hosted CI and live deployment evidence.

## Completion Report

List source files and workflows changed, Pages setting ownership, protected URL contracts, checks
performed, and any unverified publication or coexistence requirement. Record deliberate future
work on its owning declaration instead of inventing a second state file. Do not claim Pages is
enabled, a feed exists, or publication succeeded solely because configuration files were added.

## Maintaining This Skill

* MkDocs, theme and plugin compatibility, dependency-lock tooling and Mermaid rendering.
* Official Pages actions, permissions, environment protection and deployment replacement behavior.
* Project-site URL handling, generated navigation and canonical Markdown link transformation.
* Shared workflow inputs and the baseline's optional Pages settings contract.
* Catalog/feed schemas, stable public paths, collision checks and publisher hand-offs.
