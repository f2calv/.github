---
name: frontend-d3
description: 'Create, extend, audit or troubleshoot D3 browser visualizations and SVG editors: typed data, scales, keyed joins, coordinate transforms, pan/zoom, gestures, accessible controls and measured rendering performance. Use for charts, diagrams and geometry-driven editing, independent of bundler or UI framework. Vite tooling belongs to tooling-vite; offline installation belongs to frontend-pwa.'
---

# D3 Rendering and Interaction

Use D3 as a rendering/interaction adapter, not the authoritative application state. Apply the
[TypeScript/browser instructions](../../instructions/typescript.browser.instructions.md).
This skill does not require Vite, a PWA or a geometry editor.

## Boundaries

- [Vite tooling](../tooling-vite/SKILL.md) owns scaffolding and build/asset configuration when used.
- [PWA support](../frontend-pwa/SKILL.md) owns optional offline installation and updates.
- [Local documents](../../instructions/references/browser-local-documents.md) owns persistence,
  transactional history and import/export for editable visualizations.
- Domain-specific units, stock rules and shortcuts belong to the consuming application.

## Workflow

### 1. Establish the data and rendering contract

1. Inspect the data model, container, framework lifecycle and D3 modules in use. Use matching type
   declarations and import only the required modules.
2. Keep calculations and state transitions pure. Geometry, bounds, transforms, endpoints,
   tangents and snapping must not read the DOM, import D3 or persist state.
3. Document coordinate spaces and axis orientation. For physical editors use one model unit with
   explicit angle units; for charts declare data domains, scales, ranges and missing-value policy.
   Use named or branded types to distinguish model/data points, SVG user space and CSS pixels.
4. Validate finite numbers and ranges before rendering. Use stable domain IDs; connection
   references must not dangle. Derive extents and totals from the owning document revision.
5. Define physical constraints in model units and pointer hit tolerance in screen pixels.
   Document precision; do not use exact floating-point equality or round stored coordinates on
   every movement.

### 2. Render through a narrow adapter

1. Use selection and keyed data joins with stable IDs. Update and remove through the join rather
   than appending duplicates. Keep transient hover/drag previews separate from committed state.
2. When a framework also owns the DOM, give D3 a clearly isolated subtree and clean it up through
   the framework lifecycle. Do not let two renderers compete for the same elements.
3. Insert structured shapes/text under the browser instructions. Imports contain validated data,
   not arbitrary SVG/HTML. Generated SVG exports exclude scripts, event handlers, unsafe links
   and `foreignObject`; editable JSON remains a separate format.
4. Account for `viewBox`, CSS resizing, `preserveAspectRatio`, scales, pan and zoom. Handle empty
   data, missing values and changing domains without silently inventing meaningful data.
5. Maintain screen-sized hit areas and, where appropriate, `vector-effect="non-scaling-stroke"`.
   Physical scale is distinct from zoom; CSS millimetres do not guarantee actual display size.
   Physical output requires explicit calibration or export/print scaling.

### 3. Convert coordinates and own gestures

1. Map model coordinates through a declared model-to-SVG transform and viewport transform.
   Convert `clientX/clientY` through the relevant group's inverse `getScreenCTM()`, or
   `d3.pointer(event, group)` with equivalent semantics. Handle null/non-invertible matrices;
   do not equate `offsetX`, device pixels and SVG units or apply zoom twice.
2. Choose one owner per gesture: Pointer Events or D3 drag/zoom, not competing handlers for the
   same action. Define drag, selection, pan and zoom precedence and filters; controls must not
   accidentally initiate canvas gestures.
3. With Pointer Events, track `pointerId`, capture on drag start and clean up on `pointerup`,
   `pointercancel` and `lostpointercapture`. Release capture/remove temporary listeners on every
   exit path. Cancellation restores the committed snapshot.
4. Limit `touch-action` suppression to necessary gestures/surfaces. Preserve page scrolling and
   browser zoom elsewhere, or an explicit equivalent within the interaction contract.

### 4. Offer equivalent accessible editing

1. Route pointer, keyboard and toolbar operations through the same domain commands. Provide an
   accessible list or inspector for selection/properties, not only SVG hit targets or hover.
2. For editors, offer movement/rotation/connection controls and Escape to cancel. Document
   increments; avoid shortcuts while a text input or editable content has focus.
3. Preserve visible focus and touch-friendly target sizes. For charts provide meaningful labels
   and an equivalent textual/table view where needed, not only colour or mouse tooltips.
4. Keep previews reversible and commit a gesture as one undoable edit. Follow the local-document
   transaction contract if persistence/history is present.
5. Explain destructive operations before confirmation; announce committed selections and errors,
   not every pointer move.

### 5. Measure and validate

1. Batch expensive visual updates with `requestAnimationFrame` and dispose pending work with the
   view. Avoid rebuilding unrelated controls on pointer movement.
2. Measure before introducing spatial indexes, geometry caches or workers. Bound large inputs
   and invalidate caches with the owning revision.
3. With authorization, run focused domain tests for transforms, snap thresholds and connections;
   chart tests cover meaningful domain/range and missing-data behavior.
4. Use browser tests for drag cancellation, keyboard/touch alternatives, focus, zoom/resizing and
   visible errors. Test the actual rendering contract, not only generated path strings.
5. Report executed checks, static evidence and unverified browser/device behavior separately.

## Maintaining This Skill

- Recheck D3 join, pointer, scale and gesture APIs during upgrades.
- Revisit SVG accessibility, Pointer Events, framework ownership and rendering budgets when
  browser support or document size changes.
- Keep application geometry and persistence policy outside the renderer.
