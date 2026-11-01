# PVC-Safe GitOps Migration

Use this reference when changing Argo CD ownership, Application names, Helm release names, source
paths, or namespaces around stateful workloads.

## Invariants

Record these values before the first commit and compare them after every phase:

| Layer | Identity that must remain stable during an ownership refactor |
| --- | --- |
| Argo CD | Destination namespace, source revision, Helm release name |
| Kubernetes | Kind, namespace, resource name |
| PVC | UID, claim name, backing PV, storage class, access modes, capacity |
| Workload | Claim reference, volume mount, selector, service name |

A repository restructure must not change PVC UID or backing PV, Helm release name, destination
namespace, StatefulSet, Deployment, Service, Secret, or ConfigMap names, or volume claim templates
or mounted claim names.

An Argo Application name may change without changing workloads. A Helm release name, destination
namespace, StatefulSet name, or PVC name usually changes rendered Kubernetes identity and therefore
has a much larger blast radius.

## Preflight Inventory

```powershell
kubectl get applications,applicationsets -n argocd -o json
kubectl get pvc -A -o json
kubectl get pv -o json
kubectl get statefulset,deployment -A -o json
kubectl get volumesnapshot -A
```

Record:

- root and wrapper Application names, UIDs, finalizers, tracking IDs, and source paths;
- every leaf Application, destination namespace, Helm release name, and sync wave;
- raw resources currently owned directly by wrapper Applications;
- current workload readiness and restart counts.

For each PVC, capture:

- namespace/name and UID;
- `spec.volumeName`;
- storage class, access modes, requested and current capacity;
- PV reclaim policy and node affinity;
- Argo tracking annotation and owner references;
- application-level backup and restore command.

Do not proceed from a backup that has never been restored successfully.

## Building the Applications-Only Tree

Create the target tree without changing the active root. Copy or move only Argo Application
manifests. Add dedicated directory-source Applications for raw resources that wrappers currently
own. Keep source paths, namespaces, Helm release names, and Kubernetes resource names unchanged.

## Root and Wrapper Consolidation

When replacing namespace wrappers with direct root-owned leaf Applications, handle each wrapper:

1. Remove its resources finalizer in Git and reconcile that change.
2. Verify the live wrapper has no finalizer.
3. Change the root source to the Applications-only tree in one commit so direct leaf Applications
   are adopted.
4. Verify leaf Application UIDs or desired replacements are Synced/Healthy, tracking annotations
   identify the new owner, and PVC identity is unchanged.
5. Restore finalizers on the desired direct Applications.
6. Remove any finalizer-free orphan or wrapper Application only after its replacement is healthy
   and direct ownership is established.

Keep namespaces and resource names stable throughout this operation.

## Application Ownership Handoff

Use this sequence when the Kubernetes resources should stay exactly where they are:

1. Add the replacement Application manifest with the same destination, release name, and values,
   but do not let two Applications actively prune the same resources.
2. Remove the old Application's resources finalizer in Git and wait for the live finalizer to be
   absent.
3. Reconcile the replacement Application and wait for Synced/Healthy.
4. Confirm Argo tracking annotations moved to the replacement and PVC UID/PV are unchanged.
5. Delete the finalizer-free orphan Application.
6. Restore a resources finalizer on the desired Application.

For an ApplicationSet handoff:

1. Set `spec.syncPolicy.preserveResourcesOnDeletion: true` and reconcile it.
2. Wait until generated Applications no longer carry a resources finalizer.
3. Replace or remove the ApplicationSet.
4. Adopt resources with the desired plain Applications.

## Introducing AppProjects

Add project definitions before assigning dependent Applications. Pilot one low-risk namespaced
Application, test intended denials as well as successful reconciliation, and then move Applications
out of `default` incrementally. Do not combine project assignment with an ownership handoff or
namespace move.

## Namespace Migration

Kubernetes cannot rename a PVC or move it across namespaces. Treat each stateful namespace move as a
planned data migration and choose one data movement method:

- application-native backup and restore;
- CSI VolumeSnapshot plus restore into a new PVC;
- storage-system backup/restore;
- controlled file/database replication between old and new claims.

Do not edit `claimRef.namespace` on a bound PV as a routine migration technique. It bypasses normal
binding safety and is difficult to roll back consistently across CSI and GitOps controllers.

Move stateless workloads first. Never combine an App-of-Apps ownership refactor with a stateful
namespace move. Sequence stateful namespace moves independently, one workload at a time:

1. Prove backup restore or CSI snapshot/clone support, set an appropriate PV reclaim policy, and
   record the rollback point.
2. Create destination namespace, policies, secrets, and service accounts.
3. Create and verify the new PVC from a tested backup or snapshot.
4. Quiesce the old writer.
5. Perform final synchronization and start the destination workload.
6. Validate application data, mounts, probes, and clients before decommissioning the original claim.
7. Retain the old PVC through an agreed rollback window.
8. Remove old resources only after explicit approval.

## Stop Conditions

Stop immediately when:

- a PVC UID or backing PV changes during an ownership-only migration;
- an Application scheduled for deletion still has a resources finalizer;
- two Applications report ownership of the same resource;
- a new pod is Pending because PV and pod node affinity no longer intersect;
- a backup or restored dataset cannot be validated;
- unrelated Git worktree changes appear during a migration phase.
