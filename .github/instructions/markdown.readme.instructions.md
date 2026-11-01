---
description: 'README.md structure, accessibility, synchronization with code, content boundaries and generated reference tables.'
applyTo: '**/README.md'
---

# README Files

Applies to every file named `README.md`: repository root, project, sample, chart or `docs/` index.
The `docs-readme` skill owns section selection, procedure, discoverability and badges.

## Consistency

- **Every project has a `README.md`**, created in the same commit as a new project, module,
  package, chart or sample, where a project is the repository's unit of delivery.
- Keep each README in sync with its implementation. During any refactoring, and always before
  opening a pull request, update affected READMEs in the same change for renamed types, inputs and
  outputs, changed configuration options, dependency tables and diagrams.
- **Only document what exists**: describe behaviour such as encryption, resumability or retry
  semantics only once the implementation and its validation exist.
- Components with strongly typed configuration include a `## Configuration Examples` section
  progressing from minimal to fully configured.

## Structure and Accessibility

- **Exactly one `# H1`**, as the first content line, naming the repository, project or module and
  matching its package identity. Follow it with a one- or two-sentence summary of what it is and who
  it is for.
- Never skip heading levels, and keep headings unique within the file.

## Content Boundaries

- Link to focused guidance for migrations and retirements instead of reproducing release history.
- Lead with consumer needs. Omit generic key-file inventories, suppressed-warning lists, coding
  rules and maintainer checklists. Include concise development commands and unusual prerequisites
  when useful; keep detailed contributor and operational guidance in its appropriate document.
- Do not narrate a repository's internal CI jobs or release plumbing. Explain workflow inputs,
  outputs, permissions and execution flow when the workflow or action is itself the product.
- Do not duplicate local Compose wiring in READMEs: port mappings, image tags, mounts and storage
  layout belong in the Compose file and its header. Link to it; retain only necessary startup
  commands, caller configuration and data-loss warnings in the README.
- Reuse dedicated or inherited contribution, support and security guidance rather than duplicating
  it. A short link is sufficient where discovery needs help; do not create empty boilerplate sections.
- A collection's root README provides orientation and one useful catalogue. Project READMEs explain
  their own contracts and usage. Keep each published package or chart README useful when rendered
  outside GitHub; link to deeper material without moving essential installation guidance away.
- When describing a public API or surface, link each primary interface name directly to its defining
  source file, not merely to a project folder or a generic API index. Link the contract at its first
  explanatory mention or in the public-surface table; code samples need no embedded Markdown links.
  Verify the definition and source reference. Use absolute repository links in packaged READMEs
  where relative source links would not resolve in the registry.
- Put extended tutorials, design explanations and runbooks under `docs/`. Do not move essential
  usage or configuration out of a README merely to make it shorter, and do not copy entire guides
  into multiple READMEs.

## Generated Reference Documentation

Where a tool generates interface documentation (inputs, outputs, providers, resources, API surface) into a `README.md`:

- Generate it; never hand-maintain the generated tables.
- Use the source declarations' own description attributes as the canonical text. Treat comment scraping only as a fallback for declarations without a description.
- Preserve the generator's `BEGIN`/`END` marker comments around the generated block, and never edit between them.
- Regenerate after any change to the public interface or to version constraints, and commit the regenerated output in the same change.
- Keep the generator version pinned identically in the development container and in the pre-commit configuration.
- Enforce drift in both pre-commit and CI: uncommitted generated output is a failed check, not a cosmetic difference.
