---
description: 'GitOps conventions for Kubernetes clusters reconciled from Git, covering the App-of-Apps pattern, Application manifests, namespaces, naming and sync policy.'
applyTo: 'src/**/*.yaml,src/**/*.yml'
---

# Kubernetes GitOps

These rules apply to Kubernetes manifests in a repository whose cluster state is reconciled from Git
by a GitOps controller such as Argo CD or Flux. Ignore them in a repository that does not deploy
through GitOps.

## Repository Layout

Lay the manifests out so that every namespace is reached the same way — an Application file that
owns the namespace, beside a folder holding that namespace's components:

```text
src/
├── project.yaml                          # Project definition
├── bootstrap/                            # Platform and infrastructure, reconciled first
│   ├── app-of-apps.yaml                  # Root Application for this layer
│   ├── <namespace>.yaml                  # Application owning the folder below
│   ├── <namespace>/
│   │   ├── <component>.yaml              # One Application per component
│   │   ├── <component>-values-<x.y.z>.yml  # Chart values, version in the filename
│   │   └── _secrets.yaml                 # Shared resources, underscore-prefixed
│   └── archive/                          # Retired manifests, kept for reference
└── workloads/                            # Applications that depend on the platform
    ├── app-of-apps.yaml                  # Root Application for this layer
    ├── <workload>.yaml
    ├── _configmap.yaml
    ├── configmaps/                       # Per-environment configuration
    └── secrets/
```

- The `<namespace>.yaml` and `<namespace>/` pair is the important part. The file is an Application
  whose source path is the folder, so adding a component means dropping one file into the folder
  rather than editing a parent manifest.
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
- Separate the roots by concern — typically one for infrastructure and platform components, another
  for the workloads that depend on them. Infrastructure reconciles first.
- Label the roots distinctly from the applications they own, so a query can tell a root from a leaf.

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

## Namespaces

- One namespace per concern, named after the concern rather than the product that currently fills it,
  so replacing the implementation does not require renaming the namespace.
- Keep platform components in their conventional namespaces and application workloads out of them.
- Never deploy a workload into the GitOps controller's own namespace.

## Naming

- Name an Application file after the component or workload it deploys.
- Prefix a shared resource that is not itself an Application — a ConfigMap or Secret consumed by
  several workloads — so it sorts apart from the Applications, for example with an underscore.
- Store a chart values file alongside the manifest that consumes it, suffixed `-values.yaml` and
  carrying the chart version it targets, for example `<name>-values-1.2.3.yaml`. The version in the
  filename must match the chart version being deployed.
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
