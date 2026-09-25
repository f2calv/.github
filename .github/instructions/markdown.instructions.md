---
description: 'README structure and consistency, generated reference documentation and Markdown linting conventions.'
applyTo: '**/*.md'
---

# Documentation

Where these rules refer to a *project*, read it as the repository's primary unit of delivery — a project, library, module, chart, reusable workflow, action or deployment layer, whichever that repository publishes.

## README Consistency

- **Every project has a `README.md`**: when adding a new project, module, package, chart or sample, create its `README.md` in the same commit. Follow the established pattern: Purpose → Public surface → Configuration → Dependencies.
- Keep every `README.md` in sync with its implementation. During any refactoring — and **always** before opening a pull request — scan each affected `README.md` for outdated type, input or output names, missing or removed configuration options, stale dependency tables and inaccurate diagrams. Update it in the same change, never as a follow-up.
- **Major refactorings** (renames, moves, dependency-injection restructuring, type splits): update every `README.md` that mentions the old names in the same commit. Do not leave stale references behind.
- For changes spanning several projects, review all impacted `README.md` files before opening the pull request.
- **Only document what exists**: do not describe behaviour — encryption, resumability, deduplication, retry semantics, platform support — until the implementation and its tests or validation are in place.
- **Placeholders in examples**: examples must use synthetic values. Never include real credentials, tokens, connection strings, endpoints, hostnames, resource identifiers, device addresses or personal data.
- **Configuration examples**: components exposing strongly typed configuration should include a `## Configuration Examples` section with snippets progressing from minimal to fully configured, giving consumers copy-paste-ready templates.
- **Markdown tables**: separator rows use spaces around pipes to match the header and data rows (`| --- | --- |`, not `|---|---|`). This prevents MD060 (table-column-style) warnings.

### Structure and Accessibility

Apply to every file named `README.md`, wherever it lives — repository root, project, sample, chart or documentation sub-folder. These rules are specific to `README.md` and do not apply to other Markdown files.

- **Exactly one `# H1`**, as the first content line, naming the repository, project or module. Never repeat the H1 lower down and never open with `##`.
- **Never skip heading levels**: `#` → `##` → `###` in order. Skipping breaks outline extraction and MD001.
- **Lead with a one- or two-sentence summary** directly under the H1 stating what the thing is and who it is for. Search engines and package registries surface this as the description.
- **Keep the H1 aligned with the package identity** so the README title, the packaging metadata description and the published registry listing agree.
- **Descriptive link text**: never `click here`, and never a bare URL where a phrase reads better.
- **Alt text on every image** describing the content rather than the file (`![Service dependency graph](…)`, not `![diagram](…)`).
- **Unique headings within a file** so generated anchors resolve predictably.
- **No YAML front matter**: front matter belongs only to Copilot customisation files (`*.instructions.md`, `*.prompt.md`, `*.agent.md`) and to GitHub issue and pull request templates, which require it. Never add a `title:`, `description:` or `author:` block to a `README.md` or to any other documentation Markdown; GitHub renders it as a table above the content rather than as a heading, leaving the page with no `<h1>`. The `# H1` and the summary sentence beneath it already carry the title and the description.

### Root README Content

Organize a repository's primary `README.md` around the reader journey rather than forcing every
repository type into one identical outline:

1. Name the project and summarize what it does, why it is useful and who it serves.
2. Put installation or a quick start before architecture and implementation detail.
3. Document normal usage, then configuration and public interfaces where they exist.
4. Explain how to build, test and validate changes when contributors can work on the project.
5. Point readers to support, contribution, security and license information. Link to dedicated or
  inherited community-health files instead of duplicating them in the README.

Use headings appropriate to the delivery type:

| Delivery type | Expected primary sections |
| --- | --- |
| Application or CLI | Quick Start, Installation, Usage, Configuration, Development |
| Library or package collection | Installation or Quick Start, Packages or API, Configuration, Build and Test |
| GitHub Action | Usage, Inputs, Outputs when present, Testing or Development |
| Reusable workflows | Usage, Workflows, Deployment Flow, Development |
| Terraform module | Dependency Graph, Usage, generated Requirements/Providers/Resources/Inputs/Outputs, Development |
| Helm chart repository | Overview, Chart Catalogue, Usage, Versioning, Development |
| Container example | Quick Start or Run, Platform Support, Configuration, Build and Test |

Treat these as content requirements, not mandatory spelling. Omit irrelevant sections, combine
closely related material, and keep detailed tutorials or operational documentation under `docs/`.

## Generated Reference Documentation

Where a tool generates interface documentation (inputs, outputs, providers, resources, API surface) into a `README.md`:

- Generate it; never hand-maintain the generated tables.
- Use the source declarations' own description attributes as the canonical text. Treat comment scraping only as a fallback for declarations without a description.
- Preserve the generator's `BEGIN`/`END` marker comments around the generated block, and never edit between them.
- Regenerate after any change to the public interface or to version constraints, and commit the regenerated output in the same change.
- Keep the generator version pinned identically in the development container and in the pre-commit configuration.
- Enforce drift in both pre-commit and CI: uncommitted generated output is a failed check, not a cosmetic difference.

## Markdown Linting

The CI `lint` job is authoritative. Run the repository's pre-commit configuration from its root so
hook arguments and exclusions apply. Use the `pre-commit-management` skill for native execution,
the pinned Docker fallback, hook/runtime updates, fleet alignment, and troubleshooting; do not
bypass the configuration with a direct linter during normal validation.
