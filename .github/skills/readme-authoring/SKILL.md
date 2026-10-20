---
name: readme-authoring
description: 'Create, write, restructure, update and audit README.md files across simple and multi-project repositories. Use for public or private applications, CLIs, .NET and NuGet libraries, GitHub Marketplace Actions, reusable workflows, Helm charts, Terraform modules, badges, SonarQube coverage and README consistency.'
argument-hint: 'mode={create|update|audit} [scope=repository|project|workspace] [path=...]'
user-invocable: true
---

# README Authoring

Write consumer-focused READMEs from implementation evidence, using a conditional master template
rather than imposing the same outline on every repository.

## Authorities

Read these shared instructions before authoring:

- [Markdown conventions](../../instructions/markdown.instructions.md): content boundaries,
  accessibility, badges, generated reference and linting.
- [Mermaid conventions](../../instructions/markdown.mermaid.instructions.md): diagram types,
  headings, styling and synchronization.
- The target repository's instructions and applicable domain instructions.

Use the [master template](./assets/readme-template.md) for section selection. It is an annotated
authoring aid, not a document to copy unchanged. Keep documentation rules in their owning
instructions; improve this skill for procedural gaps and the template for section-selection gaps.

## Using External Best Practice

Use public guidance as evidence, not a checklist to copy. Prefer current platform documentation
over blog templates, popularity rankings or historical conventions:

| Source | Use it to verify |
| --- | --- |
| [GitHub README guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes) | Reader needs, README discovery, built-in navigation and link behavior |
| [NuGet README guidance](https://learn.microsoft.com/en-us/nuget/nuget-org/package-readme-on-nuget-org) | Package presentation, supported Markdown, image-host restrictions and preview behavior |
| [GitHub Marketplace guidance](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/publish-in-github-marketplace) | Action listing requirements and the metadata used by the listing |
| [GitHub community defaults](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file) | Supported inherited files, visibility and local override behavior |
| [Google SEO starter guide](https://developers.google.com/search/docs/fundamentals/seo-starter-guide) | Durable people-first discoverability principles, not GitHub-specific metadata controls or ranking promises |

Distinguish platform requirements from optional recommendations. Check the relevant current source
when a decision depends on renderer support, publication requirements, image hosts or inherited-file
behavior; do not freeze those capabilities or an allowlist in this skill. If verification is
unavailable, report the uncertainty rather than asserting an old limitation as current fact.

Adopt advice only when it helps this repository's readers and fits its delivery type and shared
conventions. Do not add a manual table of contents, badge wall, contributor roster, roadmap,
screenshots or redundant support sections merely because a popular template includes them.
GitHub already provides an outline; add in-document navigation only when the document or another
rendering destination benefits. Keep extended documentation under `docs/` rather than introducing
a wiki just because external guidance suggests one.

## Modes

| Mode | Outcome |
| --- | --- |
| `create` | Write missing READMEs for the requested delivery units from verified evidence. |
| `update` | Improve existing READMEs, preserving accurate useful content and generated blocks. |
| `audit` | Make no edits; report concrete findings, evidence and validation gaps. |

Do not commit, push, publish packages, execute examples or run tests without the applicable
authorization. Documentation work does not authorize deployment or live infrastructure changes.

## Workflow

### 1. Establish the Batch

1. Resolve explicit paths or active workspace folders. A workspace request includes only those
   repositories, not every clone under their parent directory.
2. Check working-tree changes and read repository notes before editing. Integrate existing edits;
   do not overwrite unrelated work.
3. Resolve each GitHub repository's visibility through the authenticated client. If it cannot be
   determined, ask before making visibility-dependent choices. Non-GitHub repositories require an
   explicit understanding of their audience and publication boundary.
4. Inventory root, project, package, chart, sample, test-project and documentation-index READMEs.
   Identify missing delivery-unit READMEs. Exclude vendored, dependency-cache and build-output files
   and report meaningful exclusions. Check which README GitHub actually surfaces when `.github/`,
   root and `docs/` entry points coexist; do not assume the root file wins.
5. Classify each delivery unit and its audience. A repository can combine several types: a CLI,
   libraries and a chart need not share one configuration section.
6. For a large workspace, work in coherent repository-sized batches. Maintain completed, remaining
   and blocked coverage in session state; do not create tracked audit receipts unless requested.

### 2. Gather Evidence

Read enough source to establish the current product, without turning the README into a source index.

| Delivery unit | Primary evidence |
| --- | --- |
| Application or CLI | Entrypoint, command definitions, configuration validation, runtime prerequisites and runnable examples |
| .NET library or NuGet package | Project and packaging metadata, target frameworks, public APIs, registration methods and usage tests |
| GitHub Action | `action.yml` or `action.yaml`, implementation, examples and verified Marketplace listing when published |
| Reusable workflow | `workflow_call` inputs, secrets, permissions, outputs, callers and supported invocation paths |
| Helm chart | Chart metadata, dependencies, values, schema, templates, OCI publication and existing generators |
| Terraform module | Variables, outputs, providers, resources, version constraints and pinned documentation generator |
| Container example | Compose or container configuration, published image, ports, mounts, health and platform support |
| Shared tooling or agent customization | Tracked skills and scripts, supported discovery locations, activation scope, prerequisites and mutation boundaries |
| Documentation index | Existing guides, intended reading order and actual navigation targets |
| Test project | Test source, project targets, fixtures, data providers, skip conditions and applicable testing instructions |

Also inspect relevant release and analysis configuration to establish current installation references
and badge destinations; this evidence does not imply the pipeline belongs in the resulting README.
Packability or a build definition does not prove publication: verify the artifact and usable version
in its registry. Give source-reference guidance for unpublished units, not speculative install commands.
Verify that advertised resources are actually tracked and distributed; an empty local directory or
an ignored resource does not establish what a fresh clone contains. For editor and agent setup,
check the selected harness's current discovery rules rather than assuming every integration uses
the same locations, precedence or Settings Sync behavior.
Reuse domain skills for their specialized procedures rather than duplicating them here.

Inspect test source as evidence where appropriate, but ask before executing tests or examples.
Separate facts established from source from behavior that still needs validation; omit unsupported
claims rather than presenting assumptions as working features.

Trace registration, provider factories and call sites before describing a capability. An enum member,
interface, XML comment or test-class name is not proof of an implemented adapter, enforced policy or
live coverage. Check who actually enforces a mode or limit: the library, a consuming host or an
external backend. Distinguish current checkout behavior from availability in a published release.
Follow actual assembly-scan boundaries and conditional dependencies in the documented build variant;
runtime feature flags do not remove compile-time dependencies, and zero replicas need not disable
other rendered resources.

For service wrappers, verify current upstream access policy and token lifecycle as well as client
methods. Cite the relevant policy and verification date when a changeable restriction affects usage;
keep that verification separate from claims of successful live execution. Trace consumer-visible
delivery behavior: deletion or acknowledgement timing, awaited versus synchronous callbacks, batching
side effects, and the scope of retries, timeouts and rate limits.

Follow invoked scripts beneath command-line flags and workflow inputs. Compare help text with
execution and packaged runtime requirements; neither a switch name nor a printed warning proves its
effect. For reusable workflows, trace secrets actually consumed, including inherited-only values
absent from the declared caller contract.

For infrastructure, trace bootstrap automation separately from the desired manifest graph; existing
manifests do not prove the documented installation path can create them. Distinguish an omitted or
null optional object from a populated object whose attributes receive defaults.

### 3. Select the Outline

1. Apply the master template's inclusion conditions to each README. Select only sections that help
   its readers, combine related sections and choose one heading for each purpose. For a public
   primary README, apply the Markdown discoverability rules and compare its summary with repository
   and registry metadata. Report metadata discrepancies separately from file edits.
2. For a simple repository, keep a single concise entry point where sufficient. Do not invent extra
   projects or documentation to satisfy the template.
3. For a collection, let the root explain the shared purpose, a useful starting example and the
   delivery-unit catalogue. Let each child explain its own installation, contract and configuration.
4. Treat a `docs/README.md` as a navigation entry point, not an application or package README.
   Other documentation under `docs/` keeps its own structure. Inspect those guides to avoid copying
   them, and edit them only when directly coupled references or facts must change.
   A test-project README serves contributors, not package consumers: use the domain testing
   instructions for its required content, and distinguish source-declared cases and skip conditions
   from observed execution results. Handle combined attributes, expand data providers, resolve
   constant-based traits and account for untagged cases. Follow every skip branch: providing
   credentials may still leave live execution explicitly disabled. Identify where fixtures replace
   real tool execution or service interaction, even when another part of the evaluation runs live.
5. Verify where a README is rendered: GitHub, NuGet, Marketplace or a chart registry. Resolve images
   and essential links for that destination; GitHub-relative links may fail in package listings.
   Check current image-host restrictions before choosing badges for a NuGet package README.
6. Decide whether a diagram improves understanding. Trace meaningful dependencies, flows or
   interactions from source, then follow the Mermaid instructions. Avoid gratuitous type, test or
   file graphs. Check renderer support; do not rely on Mermaid alone to explain essential usage
   in an external registry that cannot render it.

### 4. Write and Connect

1. Write the selected outline using current verified behavior and the Markdown content boundaries.
2. Build one catalogue instead of separate repetitive package, badge and project tables.
3. Put the shortest useful installation and usage path ahead of implementation detail. State the
   example's host context, required namespaces and configuration source. Follow the path through
   service resolution and startup; registration alone may not start a worker or receive stream.
   Verify environment-dependent configuration such as Development-only User Secrets, launch-profile
   overrides and shared secrets stores.
4. Derive configuration names, defaults, required values and examples from their definitions.
   Separate library settings from prerequisites the host or provider must supply. Make optional
   native tools and external backends conditional on the capability that needs them, rather than
   implying every consumer needs every dependency. Distinguish application overrides from library
   defaults, and label complete configurations versus merge fragments. Apply visibility and privacy
   rules before including operational context.
5. Verify badge sources and destinations under the Markdown badge rules. Use the template's badge
   patterns only after replacing placeholders with verified public metadata.
6. Preserve generator-owned content and run the pinned generator when its inputs changed. Do not
   manufacture marker names or rewrite generated tables to match the template.
7. Inspect existing contribution, support and security files and local template overrides. GitHub
   defaults from a public account-level `.github` repository can serve public and private
   repositories; local overrides may prevent inheritance. Reuse the existing guidance. Changes to
   forms, contribution policy or fleet-wide overrides are separate work unless explicitly requested.
8. Update directly affected cross-links, catalogues, package README inclusion and diagram references
   together. Do not rename or relocate documentation unless needed by the requested change.
9. For testing companion packages, document what the fake actually guarantees. Canned bytes may
   not be playable media, and substituting a provider does not bypass the surrounding validation,
   configuration or policy.

### 5. Verify and Iterate

1. Check the result against the selected template conditions, not just heading presence. Confirm
   that commands, inputs, outputs, framework versions and dependency edges match source evidence.
   Resolve command paths from the example's stated working directory, not merely by finding a
   script with the same name. Distinguish read-only audits and previews from mutating invocations.
2. Resolve local links and anchors and check relevant external destinations. Never send private
   paths or identifiers to external link checkers. Retry an apparent `HEAD` failure with `GET`
   before declaring a destination broken; some registries and badge endpoints reject `HEAD`.
   For source links, verify that the remote reference contains the defining file and contract;
   local existence does not prove availability on the default branch. Use a verified published
   immutable commit when necessary, and distinguish new documentation awaiting publication from
   broken links to existing published resources.
   Report inaccessible or unverified targets.
3. Check badge alt text against its actual metric and link, not merely whether an image loads.
   Check diagram syntax and GitHub rendering when tooling is available; disclose unrendered diagrams.
4. Follow the Markdown instructions for validation through the repository's pre-commit configuration.
   Apply the `pre-commit-management` skill when running hooks. Hooks may change files; account for
   those changes. Do not run application tests for documentation-only edits unless documentation
   tests exist and execution is approved.
5. Report changed READMEs, intentional exceptions, validation performed and blocked checks. For an
   audit, identify the file, finding and evidence rather than returning only a generic checklist.
6. On subsequent passes, preserve accepted content and repeat only the checks affected by new
   findings. Promote durable improvements into the existing owning instruction, workflow or
   template; never copy the same convention into every repository.

Completion means the requested batch is accounted for, not merely that the first root README looks
better. Report remaining repositories explicitly when a fleet request spans several batches.
