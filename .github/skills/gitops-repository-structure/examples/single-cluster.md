# Single-Cluster Discovery and Ownership

The [synthetic repository tree](../templates/single-cluster/) shows an Applications-only root,
separately seeded bootstrap permissions, and one directory-source leaf owning a ConfigMap.
It is not a complete production cluster or permission to apply these files.

## Before and After

An unsafe mixed discovery tree can look like this:

```text
src/
  bootstrap.yaml              # Root scans src/mixed recursively.
  mixed/
    example.yaml              # Application.
    example-settings.yaml     # Raw ConfigMap: root would own it too.
    example-values.yaml       # Values: not a Kubernetes resource.
```

The supplied target tree separates discovery from deployed content:

```text
bootstrap/
  example-root.yaml           # Seed AppProject; not owned by the root.
  example-projects.yaml       # Seed AppProject for the project-management leaf.
src/
  bootstrap.yaml              # Seed Application; scans only src/applications.
  applications/
    platform/app-projects.yaml
    workloads/example.yaml
  resources/
    app-projects/example-workloads.yaml
    example/manifests/example-settings.yaml
```

The before tree is a diagnostic illustration, not an executable migration fixture. Copy the
target layout only for an approved new repository. For existing resources, use the
[PVC-safe handoff procedure](../references/pvc-safe-migration.md); changing a directory does not
transfer Argo ownership safely.

## Bootstrap Inputs

The root alone cannot bootstrap this example. Before it reconciles, the approved bootstrap process
must have installed Argo CD and its CRDs in `argocd`, registered the repository, and seeded both
AppProjects under `bootstrap/`. These seed projects remain owned by that bootstrap process.
Do not let a leaf manage or prune the project it needs to authorize itself.

Replace the synthetic repository URL consistently in Applications and AppProjects. `main` is a
deliberately floating revision of the repository the operator controls, not an external dependency
pin. The conventional in-cluster API address does not select a workstation's kubeconfig context.

Configure and verify Argo CD's Application health assessment before relying on the child waves:
`app-projects` at `-10` must finish reconciling the workload AppProject before `example` at `0`.
Without that health assessment, wave numbers alone do not prove readiness or a clean bootstrap.
No controller health configuration is silently installed by these files.

## Ownership and Permission Map

| Owner | Source path | Objects it reconciles | Project grants |
| --- | --- | --- | --- |
| Approved bootstrap process | `bootstrap/`, `src/bootstrap.yaml` | Two seed AppProjects and the root Application | Administrative bootstrap authority |
| `example-root` Application | `src/applications` recursively | `app-projects` and `example` Applications | Exact repository, in-cluster destination, `argocd`, Application kind only |
| `app-projects` Application | `src/resources/app-projects` | `example-workloads` AppProject | Exact repository, `argocd`, AppProject kind only |
| `example` Application | `src/resources/example/manifests` | `example/example-settings` ConfigMap | Exact repository, `example`, ConfigMap; Namespace creation for `CreateNamespace=true` |

There are no wildcard source/destination grants, no `default` project, and no wrapper Application
whose only purpose is grouping by namespace. Raw resources are outside every root discovery path.
The sample creates the workload namespace through the sync option, not a separately owned Namespace
manifest. An AppProject's cluster-kind allowlist is not a resource-name whitelist.

This is a **trusted administrative repository**. Permission to write Applications or AppProjects
in the Argo namespace is powerful; these examples do not sandbox an untrusted contributor.
Repository access controls and Argo RBAC remain essential.

## Migration Boundaries

Moving `example.yaml` into the discovery tree must not change its Application name, source revision,
destination namespace, Helm release identity when applicable, or the names of its resources.
The root's ownership of a child Application is distinct from that child's ownership of a ConfigMap
or PVC. Verify both tracking relationships after an authorized handoff; do not fabricate tracking
annotations in source as a substitute.

All example Applications have deletion finalizers and automated pruning. That is a greenfield
steady state, **not** the intermediate state for retiring an old wrapper. Reconcile finalizer
removal/preservation and prove replacement ownership before removing an existing Application.
Never use this tree as authorization to move a namespace, replace a PVC or delete a controller.

## Acceptance Checks

Offline checks should enumerate the root's exact discovery path, require Application-only
documents, resolve each in-repository leaf source, verify project references and exact grants,
and reject overlapping raw-resource ownership. The fixture tests check these concrete files;
they are not a general Argo policy engine.

An authorized disposable-cluster check must additionally prove seed ordering, Application health
assessment, project denials, namespace creation, tracking, pruning and any required data restore.
The ConfigMap-only example intentionally omits production workloads, secrets, NetworkPolicies,
quotas and backups; it does not establish runtime isolation or a recoverable stateful deployment.
