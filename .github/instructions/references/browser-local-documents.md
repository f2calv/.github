# Browser Local Documents

Use this on-demand workflow for editable browser documents, transactional history, persistence
and import/export, regardless of rendering library, bundler or offline installation.
The [TypeScript/browser instructions](../typescript.browser.instructions.md) own validation,
failure-surfacing and accessibility invariants.

## Document and History Transactions

1. Validate a candidate revision through one command boundary before publication. Placement,
   deletion, duplication and connection changes update all domain references/derived quantities
   together. Reject dangling references, duplicate IDs and inconsistent connections; a rejected
   command leaves the entire committed snapshot unchanged.
2. Keep application-specific resource policies in the consumer. Where resources are finite,
   validate non-negative integer quantities and conservation/availability in the same transaction;
   deletion and undo/redo restore the complete revision, not separately mutated DOM counters.
3. Keep gesture previews out of history and persistence; commit each gesture as one undoable edit.
   State whether autosave is immediate or debounced, with an explicit flush path for reload/update.
   Serialize writes or compare revision IDs so stale asynchronous saves cannot overwrite newer work.

## Persistence and Conflicts

1. Choose persistence by workload: one versioned localStorage snapshot for small synchronous
   documents, IndexedDB transactions for larger/multi-record data. Independent localStorage keys
   do not provide a transaction.
2. Handle storage access, reads and writes as well as JSON parsing. Distinguish an absent document
   from denied storage, malformed JSON and unsupported format versions.
3. A failed write either rejects publication or leaves a clearly marked unsaved revision with
   retry/export. Report saved only after persistence succeeds; preserve recoverable work.
4. Detect other tabs via revisions and storage events or BroadcastChannel. Explain single-tab
   ownership or offer explicit conflict resolution; do not silently overwrite another tab's edits.
   Do not rely on unload handlers for asynchronous saving.
5. Browser storage is origin/device-local, not backup or sync. Explain permission restrictions,
   quota exhaustion, eviction and the limits of persistent-storage requests.

## Validation, Recovery and Interchange

1. Use a format identity, schema version and data envelope. Parse into `unknown`, validate the
   complete structure and limits, migrate explicitly supported older formats, then validate again.
   Reject future versions without overwriting. Never merge untrusted objects into app configuration.
2. Validate units, finite values, item kinds, IDs, references and resource consistency. Bound file
   size, nesting/collection sizes and string lengths before expensive work.
3. On startup failure retain original readable bytes and offer download, retry or explicit reset.
   Never replace unreadable data silently with an empty saved document.
4. Export self-contained versioned JSON through a Blob/download link and revoke the object URL.
   A browser download is not proof of a durable backup. Generated SVG/image export is separate
   from an editable document and must contain only safe, validated content.
5. Import through a file input with explicit asynchronous errors. Parse/migrate/validate off to the
   side, preview replacement or merge effects, and apply one transaction after confirmation.
   Remap colliding IDs/references for merges and revalidate domain quantities.
   Cancellation or failure preserves existing work; avoid stale import completion replacing newer edits.

## Validation Scenarios

With permission, exercise rejected commands, undo/redo, schema migration/future versions,
oversized/malformed imports, denied/quota-failed storage and conflicting tabs. For reload or
worker updates, finish/cancel gestures and flush successful persistence first; save failure blocks
reload and offers recovery/export. Update ownership remains with the app's service-worker integration.
