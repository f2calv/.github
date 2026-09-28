---
name: gitops-repository-structure
description: 'Restructure App-of-Apps repositories, isolate namespaces and migrate Argo CD ownership without deleting PVCs.'
argument-hint: '[repository=path] [scope={audit|plan|migrate}]'
user-invocable: true
---

# GitOps Repository Structure

Design or migrate an Argo CD App-of-Apps repository without treating directory neatness as a
runtime boundary. Keep root discovery restricted to Argo Applications, use sync waves for ordering,
and separate Application ownership changes from namespace and data migrations.

## Prerequisites

- Read-only access to the Git repository and cluster
- `git`, `kubectl`, and `yq`
- A current backup or snapshot mechanism for every stateful workload in migration scope
- Explicit approval before committing, pushing, or changing live Argo CD resources

## Quick Start

1. Inventory root Applications, child Applications, sync waves, destination namespaces, and source
   paths.
2. Inventory PVC UID, PV, reclaim policy, storage class, access mode, node affinity, and Argo
   tracking ID.
3. Design an Applications-only discovery tree and keep raw resources outside it.
4. Migrate Application ownership first without changing namespaces or Kubernetes resource names.
5. Migrate namespaces later, one workload at a time, with explicit data movement.

See [the PVC-safe migration reference](references/pvc-safe-migration.md) before changing any
Application, ApplicationSet, Helm release name, namespace, StatefulSet, or PVC.

## Target Model

Use one seeded root Application for one cluster when access and lifecycle boundaries permit it:

```text
src/
├── bootstrap.yaml
├── applications/
│   ├── platform/
│   │   ├── app-projects.yaml
│   │   ├── ingress-controller.yaml
│   │   └── storage-controller.yaml
│   └── workloads/
│       └── example.yaml
└── resources/
   ├── app-projects/
   │   └── projects.yaml
   └── example/
      ├── manifests/
      ├── values/
      └── chart/
```

The root source is `src/applications` with recursive directory discovery. Every YAML file
there must be an Argo CD `Application` or `ApplicationSet`. Leaf Applications may point to Helm
repositories, OCI charts, or directories under `resources/`.

Do not recursively scan `src` itself. A mixed tree eventually applies a Secret, values
file, archived manifest, or Helm template as though it were an Argo Application.

## Dependency Ordering

Put `argocd.argoproj.io/sync-wave` on direct child Applications:

| Typical wave | Responsibility |
| --- | --- |
| `-4` | Cluster networking and storage prerequisites |
| `-3` | Certificate and security controllers |
| `-2` | GitOps controller self-management |
| `0` | Shared operators and data services |
| Positive | Observability and application workloads |

Use the numbers as a repository-specific dependency graph, not a universal taxonomy. Argo advances
only after earlier-wave child Applications become healthy when health assessment is configured for
the Argo CD `Application` custom resource. Verify that configuration before relying on waves for a
clean-cluster bootstrap. A sync wave does not replace runtime readiness, CRD availability checks, or
application retry behavior.

## Authorization Boundaries

Use AppProjects to restrict each class of Application:

- allow only intended source repositories;
- allow only intended destination clusters and namespaces;
- allow cluster-scoped resources only for platform controllers that need them;
- constrain namespaced resource kinds for ordinary workloads;
- give the root only the permissions needed to create approved child Applications.

The root's own project must pre-exist. Seed it with the root, or initially use a deliberately
constrained pre-existing project. Reconcile all other AppProjects through an earliest-wave leaf
Application before Applications that reference them. Do not leave every leaf in an unrestricted
`default` project after bootstrap validation.

## Namespace Boundaries

Create namespaces around trust, ownership, policy, and lifecycle:

- Keep cluster operators in conventional namespaces.
- Give an independently operated application its own namespace.
- Co-locate a database with its sole owning application when policy and operations align.
- Use a shared-service namespace only when several applications deliberately share the service.
- Avoid broad `utilities`, `data`, `apps`, `prd`, or `tst` namespaces as permanent ownership models.

Environment can remain a label, configuration dimension, or suffix where multiple instances are
required. It should not be the only isolation boundary between unrelated applications.

## Required Migration Workflow

### 1. Inventory Before Editing

Record:

- root and wrapper Application names, UIDs, finalizers, tracking IDs, and source paths;
- every leaf Application, destination namespace, Helm release name, and sync wave;
- raw resources currently owned directly by wrapper Applications;
- every PVC and its UID, PV, reclaim policy, storage class, access mode, capacity, node affinity,
  owner references, and Argo tracking ID;
- current workload readiness and restart counts.

### 2. Build the Applications-Only Tree

Create the target tree without changing the active root. Copy or move only Argo Application
manifests. Add dedicated directory-source Applications for raw resources that wrappers currently
own. Keep source paths, namespaces, Helm release names, and Kubernetes resource names unchanged.

### 3. Remove Wrapper Ownership Safely

For each wrapper Application:

1. Remove its resources finalizer and reconcile that change.
2. Verify the live wrapper has no finalizer.
3. Switch the root to the Applications-only tree so direct leaf Applications are adopted.
4. Verify direct child Applications are Synced/Healthy and tracking annotations identify the new
   owner.
5. Restore finalizers on the desired direct Applications.
6. Remove any finalizer-free orphan Application only after its replacement is healthy.

For an ApplicationSet, set `spec.syncPolicy.preserveResourcesOnDeletion: true`, reconcile it, and
verify generated Applications no longer carry a resources finalizer before deleting the set.

### 4. Verify Resource Identity

Compare pre- and post-migration values. A repository restructure must not change:

- PVC UID or backing PV;
- Helm release name;
- destination namespace;
- StatefulSet, Deployment, Service, Secret, or ConfigMap names;
- volume claim templates or mounted claim names.

### 5. Migrate Namespaces Separately

A PVC cannot be renamed or moved to another namespace. Treat each stateful namespace move as a
planned data migration:

1. Prove backup restore or CSI snapshot/clone support.
2. Set an appropriate PV reclaim policy and record the rollback point.
3. Quiesce writers.
4. Restore or clone into a new PVC in the destination namespace.
5. Validate data and application behavior before decommissioning the original claim.

Move stateless workloads first. Never combine an App-of-Apps ownership refactor with a stateful
namespace move.

## Validation

After every phase:

```powershell
kubectl get applications,applicationsets -n argocd
kubectl get pvc,pv -A
kubectl get pods -A
git diff --check
```

Also verify:

- the intended Applications are Synced and Healthy;
- no old Application retains a resources finalizer before deletion;
- PVC UID/PV mappings match the inventory;
- workloads have the expected ready replicas and restart counts;
- warning events and application logs show no storage or mount failures;
- the Git worktree contains no unrelated changes before each commit.

## Troubleshooting

| Symptom | Response |
| --- | --- |
| Root tries to apply a Secret or values file | Restrict its source to the Applications-only tree |
| Shared-resource warning during adoption | Remove old ownership safely, then let one desired Application adopt it |
| Application deletion starts pruning workloads | Stop; remove/reconcile its finalizer or preserve generated resources before deletion |
| New namespace cannot bind the old PVC | Restore/clone data into a new claim; PVCs are namespace-scoped |
| Stateful pod remains Pending after placement change | Check PV node affinity and storage replicas before changing selectors |
| Earlier sync wave is stuck | Inspect child Application health and CRD/controller readiness; do not bypass ordering blindly |

> Brought to you by f2calv/.github
