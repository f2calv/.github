---
name: frontend-pwa
description: 'Create, extend, audit or troubleshoot progressive web apps: manifests and icons, installation, production service workers, offline caches, deployment scope, safe updates and multi-tab/schema coordination. Use when a browser application needs installability or reliable offline behavior, independent of bundler and renderer. Vite build tooling belongs to tooling-vite; D3 interaction belongs to frontend-d3.'
---

# Progressive Web Apps

Add offline/install behavior without compromising user work. Apply the
[TypeScript/browser instructions](../../instructions/typescript.browser.instructions.md) and
[local-document recovery/update contract](../../instructions/references/browser-local-documents.md).
Neither Vite nor D3 is required. Follow existing execution and deployment approvals.

## Boundaries

- [Vite tooling](../tooling-vite/SKILL.md) owns build/base configuration when Vite is used.
- [D3 interaction](../frontend-d3/SKILL.md) owns optional graphical editing and gesture cancellation.
- User documents live separately from app caches; installation is not backup or cloud sync.

## Workflow

### 1. Choose the worker and installation contract

1. Inspect the framework/bundler's existing worker owner, manifest, hosting path and browser targets.
   Choose one owner: a supported integration or an explicit worker, never competing registrations.
2. Register only for the intended production build over HTTPS or localhost, with feature detection
   and an actionable fallback. Review generated registration and precache behavior.
3. Supply a valid manifest with appropriate name, display mode, start URL, scope and real icons.
   Include common 192x192 and 512x512 install icons; advertise maskable purpose only for an icon
   designed with its safe area. Verify every referenced file and provide platform-specific icons
   where required. Installation availability varies by browser; do not promise native packaging.
4. With Vite, use its build/base contract and a compatible PWA integration; check plugin peers and
   defaults. Keep this integration conditional rather than requiring a bundler migration.

### 2. Cache a coherent production release

1. Generate a revisioned precache of the built shell, lazy chunks, fonts and required static assets.
   Prefer locally bundled assets to runtime CDNs. Installation must complete before the release
   is usable offline; do not call a partially cached shell offline-ready.
2. Resolve worker URL/scope, precache URLs, manifest start URL/scope, icons and navigation fallback
   against one deployment base. Verify both root and subpath hosting.
3. Keep navigation fallback in scope and exclude asset/API requests. Do not redirect every failed
   fetch to HTML or cache development/HMR responses.
4. Keep release caches separate from localStorage/IndexedDB user documents. Activation deletes
   only obsolete caches this app owns, never all origin caches or user data.
5. Maintain a coherent asset set for existing open clients during rollout; do not delete chunks
   still needed by an older tab.

### 3. Update without losing edits

1. Default to a waiting worker and explicit update notification. Do not enable automatic
   `skipWaiting`, `clientsClaim` or unconditional `controllerchange` reload with pending edits/writes.
2. Before user-approved update, finish/cancel gestures and persist the latest revision through the
   local-document contract. Offer export on save failure; failure blocks reload.
3. Coordinate readiness across open tabs before takeover. Reload once when the agreed worker
   controls the page, preserving recovery.
4. Keep schema migrations compatible with live clients or require all clients to close/reload
   before migration. An older tab must not overwrite migrated data with an old schema.
5. Distinguish first visit, offline-ready, offline-but-unsaved, waiting update and failed update.
   First-ever offline visits cannot work without prior caching; installation alone does not protect
   documents from eviction or storage failure.

### 4. Validate on production output

1. With authorization, run the build and inspect manifest, worker scope and precache entries.
   Neither icon presence nor a successful build proves offline readiness.
2. Test root and intended subpath: initial online load, offline refresh/lazy assets, navigation,
   dirty-document update, failed saves, multi-tab updates and owned-cache cleanup.
3. Test installation/offline launch on target physical devices where possible. Separate emulation
   evidence from Safari/iOS, Android and other real-device results.
4. Document HTTPS requirements, browser-dependent installation, cache eviction, export/recovery,
   update behavior and origin-local data. Report deployment/device checks not performed.

## Maintaining This Skill

- Recheck worker lifecycle, manifest/install criteria, cache cleanup and browser storage behavior.
- Recheck integration registration defaults and multi-tab updates when dependencies change.
- Keep hosting configuration with its build-tool owner and data transactions in the shared reference.
