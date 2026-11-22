---
description: 'TypeScript and browser JavaScript invariants: strict types, untrusted data narrowing, DOM boundaries, event lifetimes, visible failures and accessible controls.'
applyTo: '**/*.ts,**/*.tsx,**/*.mts,**/*.cts,**/*.js,**/*.jsx,**/*.mjs,**/*.cjs,**/tsconfig*.json'
---

# TypeScript and Browser JavaScript

TypeScript rules apply to TypeScript sources and configuration; browser rules apply only to code
that runs in the browser. Use the
[Vite skill](../skills/tooling-vite/SKILL.md) for build tooling,
[D3 skill](../skills/frontend-d3/SKILL.md) for visualization and graphical interaction, and
[PWA skill](../skills/frontend-pwa/SKILL.md) for offline installation and updates.
[Local-document guidance](references/browser-local-documents.md) owns transactional persistence,
history and import/export. Other frameworks retain their own composition and rendering conventions.

## Types and Boundaries

- Enable TypeScript `strict`, `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`. Use
  `import type` for type-only dependencies and the project's module conventions.
- Treat parsed JSON, browser storage, imported files and external messages as `unknown`. Narrow
  through runtime validation before use; a cast, generic deserializer or `satisfies` expression is
  not validation. Validate nested values and domain constraints, not only the outer shape.
- Prefer discriminated unions and exhaustive handling for modes, commands and result states.
  Avoid `any`, unchecked non-null assertions and double casts; narrow indexed lookups, event
  targets and optional values explicitly.
- Separate pure domain calculations and state transitions from DOM, framework rendering and
  storage adapters. Rendering reflects state; DOM attributes are not the domain source of truth.

## Browser Rendering and Lifetimes

- Narrow queried elements and event targets by their actual element type. Handle a missing mount
  point with an actionable startup error rather than an assertion followed by a blank page.
- Insert user-controlled text with `textContent` or equivalent text APIs, not `innerHTML`,
  `insertAdjacentHTML` or D3 `.html()`. Create SVG elements in the SVG namespace; allowlist
  imported attributes and URL schemes rather than inserting imported markup.
- Own and dispose event listeners, observers, timers and subscriptions when a view is replaced.
  Use abort signals where supported and make initialization safe against duplicate registration.
- Handle asynchronous event work explicitly: catch failures at the UI boundary and prevent stale
  completions from overwriting newer state. Do not silently swallow errors or leave rejected
  promises unobserved.
- Surface loading, empty, invalid-input and failed-operation states in the interface. Preserve
  recoverable work after a failure; distinguish in-memory edits from confirmed persistence.

## Accessible Interaction

- Prefer native buttons and form controls with visible labels and accessible names. Custom
  graphics need a keyboard-operable control or an equivalent accessible editing surface.
- Preserve visible focus, logical tab order, and dialog focus containment/restoration. Provide
  text for status as well as colour and announce consequential changes without flooding live regions.
- Give pointer operations keyboard and non-drag alternatives; do not require hover, precise mouse
  targeting or a gesture as the only way to perform an action. Keep browser zoom and scrolling
  available outside the interaction surface.
