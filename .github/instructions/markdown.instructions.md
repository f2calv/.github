---
description: 'Markdown conventions for every .md file: ownership boundaries, examples, tables, links, images, front matter and linting.'
applyTo: '**/*.md'
---

# Markdown

README rules live in `markdown.readme.instructions.md` and the `docs-readme` skill; diagram rules in
the Mermaid instructions and the `docs-architecture-diagrams` skill. Domain instructions and skills
own technical contracts: link to them rather than copying their rules. Markdown under `docs/` serves
its own audience; tutorials, references, design notes and runbooks need not follow the README
template.

## Conventions

- Examples use synthetic values only: never real credentials, tokens, connection strings, endpoints,
  hostnames, resource identifiers, device addresses or personal data.
- Table separator rows put spaces around pipes (`| --- | --- |`) to satisfy MD060.
- Use descriptive link text, never `click here` or a bare URL where a phrase reads better.
- Give every image alt text that describes its content, not its file.
- No YAML front matter in documentation. Reserve it for customization files (`SKILL.md`,
  `*.instructions.md`, `*.prompt.md`, `*.agent.md`) and formats that require it.
- Describe the current product, not its rename or refactoring history; keep only actionable notices
  such as a migration or retirement warning.

## Markdown Linting

The CI `lint` job is authoritative. Run the repository's pre-commit configuration from its root so
hook arguments and exclusions apply. Use the `tooling-pre-commit` skill for native execution,
the pinned Docker fallback, hook/runtime updates, fleet alignment, and troubleshooting; do not
bypass the configuration with a direct linter during normal validation.
