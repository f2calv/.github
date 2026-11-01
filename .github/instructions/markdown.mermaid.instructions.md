---
description: 'Always-on Mermaid diagram synchronization and placement invariants; the docs-architecture-diagrams skill owns diagram selection, headings and styling.'
applyTo: '**/*.md'
---

# Mermaid Diagrams

Use the `docs-architecture-diagrams` skill to create, update or audit a Mermaid diagram. It owns the
view set, diagram-type selection, standard headings, shapes, styling, README versus `docs/`
placement and rendering checks. The rules below apply to every change, whether or not a diagram is
the subject of the change.

## Placement

- A repository's root `README.md` holds at most one overview diagram, usually the System Context.
  Deeper views live under `docs/` and the README links to them.
- Draw each view once. Link to an existing diagram rather than repeating it in another document.
- Documentation diagrams describe the current code. A proposed target view belongs in an ADR until
  the code matches it.

## Synchronisation

- Diagrams must stay in sync with the code, configuration or pipeline they describe.
- When renaming a component, input or output, update the corresponding diagram nodes in the same change.
- When adding or removing a dependency, update the dependency graph in the same change.
- When moving code between components, update the components view and its code map in the same change.
- Review every diagram in an affected `README.md` or `docs/` page before opening a pull request.
