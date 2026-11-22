---
name: tooling-vite
description: 'Create, configure, upgrade or troubleshoot Vite projects: scaffolding, TypeScript checks, dependency compatibility, assets, environment exposure, production base paths and static-host behavior. Use for Vite build tooling with vanilla code or a UI framework. D3 rendering belongs to frontend-d3; installation, offline caching and service-worker updates belong to frontend-pwa.'
---

# Vite Tooling

Own the development and production build contract without prescribing a rendering library,
framework or backend. Apply the [TypeScript/browser instructions](../../instructions/typescript.browser.instructions.md).
Follow the caller's installation, build/test and deployment permissions.

## Boundaries

- [D3 rendering](../frontend-d3/SKILL.md) owns data joins, graphical coordinates and gestures.
- [PWA support](../frontend-pwa/SKILL.md) owns manifests, workers, caching and update safety.
- Framework composition remains with its framework owner; neither related skill is required for Vite.

## Workflow

### 1. Inspect or scaffold the project

1. Read the package manifest, lockfile, runtime/package-manager pins, TypeScript configurations,
   Vite configuration and hosting contract. Preserve existing scripts and framework integration.
2. For a new project, use the matching Vite template within installation approval; do not
   regenerate an existing project. Choose vanilla TypeScript only when no framework is needed.
3. Check the scaffold's TypeScript, Vite, ESLint/typescript-eslint and any framework/PWA plugin
   peer ranges together. Choose a supported combination, not every latest release indiscriminately.
   Never bypass dependency conflicts with `--force` or `--legacy-peer-deps`.
4. Keep application entrypoints thin; pure domain modules must remain importable without the
   browser. Use bundled declarations or matching `@types` packages for dependencies actually used.

### 2. Establish checks and reproducible builds

1. Vite transpiles TypeScript but does not type-check it. Provide `tsc --noEmit` or the existing
   project-build equivalent alongside `vite build`; check build/test configuration files too.
2. Use the lockfile and the package manager's frozen-install command for CI. Keep development,
   type checking, linting, formatting, tests, production build and preview explicitly distinguishable.
3. Prefer a supported upstream fix for vulnerable transitive dependencies. A temporary override
   must be limited to the affected subtree, with a rationale and upstream removal trigger.
   Validate parent compatibility and the resolved lockfile through authorized builds and relevant
   behavior checks. A clean audit alone is not compatibility evidence; no unrelated global overrides.

### 3. Resolve assets and public configuration

1. Derive production `base` from the real hosting path. Use Vite asset imports or
   `new URL('./asset.svg', import.meta.url)` for bundled assets and `import.meta.env.BASE_URL`
   for public assets. Do not hardcode `/assets/` or development URLs.
2. A relative base requires explicit resolution for navigation and worker scope when applicable.
   Pass the hosting contract to the PWA owner rather than maintaining separate base assumptions.
3. Treat client-exposed environment values as public configuration, not secrets. Validate required
   values and never rely on server-only credentials in a browser build.
4. Keep HMR separate from production behavior. Static deployments cannot rely on the development
   server's history fallback: use suitable paths or verify the host's routing/fallback behavior.

### 4. Validate the actual production contract

1. With authorization, run existing type checks and production builds and inspect generated
   paths. A successful build does not establish offline behavior, accessibility or correct routing.
2. Verify preview at the intended base, including direct navigation, asset URLs and reloads.
   A successful root preview is not proof of project-subpath hosting.
3. If offline support is selected, use the PWA skill's production tests. Do not cache HMR responses
   or infer worker behavior from a development demo.
4. Report executed checks, static inspection and remaining host-specific verification separately.

## Maintaining This Skill

- Recheck Vite templates, asset/base resolution, environment exposure and TypeScript/plugin
  compatibility when dependencies change.
- Keep framework-specific rendering, deployment automation and worker lifecycle guidance with
  their owners instead of expanding this build-tool skill.
