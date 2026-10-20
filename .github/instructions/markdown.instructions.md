---
description: 'Markdown conventions, README content boundaries and consistency, generated reference documentation and linting.'
applyTo: '**/*.md'
---

# Documentation

Where these rules refer to a *project*, read it as the repository's primary unit of delivery — a project, library, module, chart, reusable workflow, action or deployment layer, whichever that repository publishes.

## Scope and Ownership

Use the `readme-authoring` skill to create, restructure, update or audit READMEs. Its conditional
master template owns section selection and ordering; this file owns documentation conventions.
The Mermaid instructions own diagram selection, styling and synchronization. Domain instructions
and skills own technical contracts; reference them rather than copying their rules.

README-specific rules below apply to every file named `README.md`, including project and `docs/`
index files. Other Markdown under `docs/` serves its own audience and purpose: tutorials, reference,
design explanations and runbooks need not follow the README template. Generated-reference and
linting rules apply wherever their stated conditions hold.

## README Consistency

- **Every project has a `README.md`**: when adding a new project, module, package, chart or sample, create its `README.md` in the same commit. Select relevant sections from the skill's master template.
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
- **No YAML front matter in documentation**: reserve it for customization files (`SKILL.md`, `*.instructions.md`, `*.prompt.md`, `*.agent.md`) and templates whose format requires it. Never add a `title:`, `description:` or `author:` block to ordinary documentation; use the H1 and summary instead.

### Content Boundaries

- Describe the current supported product, not its relocation, rename or refactoring history.
  Remove retrospective explanations rather than accumulating a narrative of past changes. Retain
  only actionable notices needed by current consumers, such as a breaking-change migration or
  retirement warning; link to focused guidance instead of reproducing release history.
- Lead with consumer needs. Omit generic key-file inventories, suppressed-warning lists, coding
  rules and maintainer checklists. Include concise development commands and unusual prerequisites
  when useful; keep detailed contributor and operational guidance in its appropriate document.
- Do not narrate a repository's internal CI jobs or release plumbing. Explain workflow inputs,
  outputs, permissions and execution flow when the workflow or action is itself the product.
- Reuse dedicated or inherited contribution, support and security guidance rather than duplicating
  it. A short link is sufficient where discovery needs help; do not create empty boilerplate sections.
- A collection's root README provides orientation and one useful catalogue. Project READMEs explain
  their own contracts and usage. Keep each published package or chart README useful when rendered
  outside GitHub; link to deeper material without moving essential installation guidance away.
- Put extended tutorials, design explanations and runbooks under `docs/`. Do not move essential
  usage or configuration out of a README merely to make it shorter, and do not copy entire guides
  into multiple READMEs.

### Public Primary README Discoverability

Apply these principles to a public repository's primary README, not as an SEO checklist for private
repositories or every internal guide:

- Keep the actual product identity in the H1. In the opening summary, naturally name the product
  category, important platform or ecosystem, problem solved and intended users. Explain unfamiliar
  names and acronyms instead of assuming readers already know the project.
- Use terms potential users would search for in useful prose, descriptive headings, examples and
  link text. Prefer a concrete capability description over vague marketing claims.
- Keep essential explanations as searchable text, not only in badges, screenshots or diagrams.
  Link relevant public package listings and documentation with meaningful text.
- Keep the README's description consistent with current repository and registry metadata. Flag
  inaccurate descriptions, topics or website links, but do not change GitHub settings without
  authorization.
- Do not add keyword lists, repeated synonyms, hidden text, frontmatter or HTML metadata as an SEO
  workaround. GitHub controls the page metadata; README edits cannot guarantee indexing or ranking.

### Badges and External Destinations

- Use a small set of useful live badges, not manually maintained version or coverage graphics.
  Put repository-wide badges after the summary and per-package versions in the collection catalogue.
- Make badges clickable: package versions lead to the matching package, Marketplace badges to the
  verified listing, CI status to its workflow, and analysis metrics to the matching project or metric.
- Match alt text, metric, destination and branch. Code smells are not coverage, and a Quality Gate
  is not a test result. Do not imply analysis or Marketplace publication exists without evidence.
- Resolve package IDs, listings, workflow paths and analysis keys from authoritative configuration
  or verified service metadata, not guessed naming conventions. Verify both image and link targets.
- For private repositories, check whether a badge is accessible to its audience and whether its URL
  or image request discloses identifiers to an external service. Do not add credentials, proxy
  tokens or private coordinates to public badge services; omit an unsuitable badge.

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
