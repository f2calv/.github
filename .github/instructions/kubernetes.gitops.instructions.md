---
description: 'GitOps conventions for Kubernetes clusters reconciled from Git, covering the App-of-Apps pattern, Application manifests, namespaces, naming and sync policy.'
applyTo: 'src/**/*.yaml,src/**/*.yml'
---

# Kubernetes GitOps

These rules apply to Kubernetes manifests in a repository whose cluster state is reconciled from Git
by a GitOps controller such as Argo CD or Flux. Ignore them in a repository that does not deploy
through GitOps.

## Repository Layout

Keep the root App-of-Apps source restricted to Argo CD `Application` and `ApplicationSet` manifests.
Do not recursively scan a mixed tree containing Kubernetes resources, values files, or local charts.
The default layout is:

```text
src/
├── bootstrap.yaml                        # Seeded root; source is applications/
├── applications/                         # Applications only; recursive root scan is safe
│   ├── platform/
│   │   ├── app-projects.yaml
│   │   └── <application>.yaml
│   └── workloads/
│       └── <application>.yaml
└── resources/                            # Never scanned directly by the root
  ├── app-projects/
  │   └── projects.yaml
  └── <application>/
    ├── values/
    ├── manifests/
    └── chart/
```

- Let the root discover direct leaf Applications recursively. Do not add one wrapper Application per
  namespace merely to discover the Applications in a sibling folder; it adds another finalizer and
  ownership boundary without adding isolation.
- Use a directory-source leaf Application when raw resources must be reconciled together. Point it
  at a folder under `resources/`; do not place those resources in the root's Applications-only tree.
- Keep a separate root only when layers have genuinely independent bootstrap, access, or lifecycle
  boundaries. Use sync waves within one root for ordinary dependency ordering.
- Keep a retired manifest in an `archive/` folder rather than deleting it, so the reasoning behind a
  past decision stays available. Ensure the controller does not scan it.

## Core Principles

- Git is the single source of truth. The cluster must reflect the state in Git at all times.
- Never run `kubectl apply`, `kubectl edit`, `kubectl scale` or `kubectl delete` to change desired
  state. Edit the manifest and commit it; let the controller reconcile. Read-only commands such as
  `get`, `describe`, `logs` and `exec` are fine for diagnosis.
- Treat a manual cluster change as an incident, not a shortcut. A self-healing controller reverts it
  and the fix is lost.
- Everything is declarative. A step that cannot be expressed as a committed manifest belongs in a
  documented runbook, not in tribal knowledge.

## App-of-Apps Pattern

- Use a root Application that deploys other Applications, so the whole cluster bootstraps from one
  manifest.
- Put dependency order on direct child Applications with `argocd.argoproj.io/sync-wave`. A root
  waits for an earlier-wave child Application to become healthy before advancing only when Argo CD
  has health assessment configured for its `Application` custom resource. Configure and verify that
  assessment before depending on child waves for a clean-cluster bootstrap.
- Label the roots distinctly from the applications they own, so a query can tell a root from a leaf.
- Seed the root outside the directory it scans, or point it at a dedicated `applications/` child, so
  it never attempts to reconcile itself.

## Application Manifests

- Give every Application the same shape: metadata and labels, a project, a destination server and
  namespace, a source, and a sync policy. Consistency is what makes bulk review possible.
- Add the controller's deletion finalizer so removing an Application also removes the resources it
  created, rather than orphaning them.
- Pin a chart or manifest source to an explicit version or revision. Reserve a floating revision for
  a repository you control and reconcile deliberately.
- Enable automated sync with pruning and self-healing unless there is a stated reason not to.
  Document any Application that deliberately opts out.
- Create the target namespace through a sync option rather than a separate committed manifest.

## Projects

- Use AppProjects as authorization boundaries, not only as labels. Restrict source repositories,
  destination clusters and namespaces, namespaced resource kinds, and cluster-scoped resource kinds.
- The root's own project must exist before the root. Seed that project with the root, or initially
  use a deliberately constrained pre-existing project. Reconcile all other AppProjects through an
  earliest-wave directory-source Application before Applications that reference them.
- Give the root only the permissions required to create approved child Applications. Keep broad
  cluster-resource permissions in platform projects and out of workload projects.
- Do not leave every leaf in an unrestricted `default` project once the initial bootstrap works.

## Namespaces

- Treat a namespace as a security, ownership, policy, and lifecycle boundary. Give an application or
  tightly coupled service suite its own namespace by default; do not group unrelated workloads into
  broad `utilities`, `data`, `apps`, or environment-only namespaces for tidiness.
- Keep shared operators in their conventional namespaces. Place tenant data-plane resources in the
  tenant application's namespace when ownership is exclusive; use a dedicated shared-service
  namespace only when several applications intentionally share one service and policy boundary.
- Keep platform components in their conventional namespaces and application workloads out of them.
- Never deploy a workload into the GitOps controller's own namespace.
- Namespace changes are data migrations, not manifest moves. A PVC cannot move between namespaces;
  snapshot or back up the data and restore it into a new claim rather than deleting/recreating the
  original claim during a repository restructure.

## Naming

- Name an Application file after its `metadata.name` by default, so the filename identifies the
  Argo CD object a reviewer and operator will inspect. Keep a different established name only for a
  documented controller constraint.
- Prefix a shared resource that is not itself an Application — a ConfigMap or Secret consumed by
  several workloads — so it sorts apart from related resources, for example with an underscore.
  Keep it outside the Applications-only discovery tree.
- Store a chart values file in the consuming application's folder under `resources/`, suffixed
  `-values.yaml` and carrying the chart version it targets, for example
  `<name>-values-1.2.3.yaml`. The version in the filename must match the chart version being deployed.
- Be deliberate about the file extension. A controller configured to scan for `*.yaml` silently
  ignores `*.yml`, which is a useful way to park a manifest but a confusing way to lose one.

## Ingress

- When adding a deployment backed by an external chart that supports ingress, include the full
  ingress configuration but leave it commented out in the initial commit. That gives a
  ready-to-enable template without exposing the service before it has been verified.

## Secrets

- Never commit a plaintext Secret. Use a sealed, encrypted or externally sourced secret so the
  manifest is safe to store in Git.
- Reference a secret by name from the workload manifest and keep its value out of the repository,
  out of values files and out of generated output.

## Diagrams

Beyond the shared Mermaid guidance in `markdown.instructions.md`:

- Use `flowchart` for deployment flows and controller sync chains, such as the App-of-Apps
  hierarchy, and `graph` for chart dependencies, resource relationships and namespace organisation.
- Group applications and namespaces in subgraphs named after the root that owns them.
- Use `classDef` to distinguish infrastructure applications from workload applications.
- Use the stadium shape `([ ])` for an Application.
