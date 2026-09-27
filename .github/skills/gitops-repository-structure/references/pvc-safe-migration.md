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

For each PVC, capture:

- namespace/name and UID;
- `spec.volumeName`;
- storage class, access modes, requested and current capacity;
- PV reclaim policy and node affinity;
- Argo tracking annotation and owner references;
- application-level backup and restore command.

Do not proceed from a backup that has never been restored successfully.

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

1. Set `spec.syncPolicy.preserveResourcesOnDeletion: true`.
2. Wait until generated Applications no longer carry a resources finalizer.
3. Replace or remove the ApplicationSet.
4. Adopt resources with the desired plain Applications.

## Root and Wrapper Consolidation

When replacing namespace wrappers with direct root-owned leaf Applications:

1. Build the new Applications-only tree without changing the current root.
2. Add leaf Applications for raw-resource folders currently owned directly by wrappers.
3. Remove wrapper finalizers and wait for reconciliation.
4. Change the root source to the new tree in one commit.
5. Verify leaf Application UIDs or desired replacements, tracking IDs, health, and PVC identity.
6. Remove finalizer-free wrapper objects after direct ownership is established.

Keep namespaces and resource names stable throughout this operation.

## Namespace Migration

Kubernetes cannot move a PVC object across namespaces. Choose one data movement method:

- application-native backup and restore;
- CSI VolumeSnapshot plus restore into a new PVC;
- storage-system backup/restore;
- controlled file/database replication between old and new claims.

Do not edit `claimRef.namespace` on a bound PV as a routine migration technique. It bypasses normal
binding safety and is difficult to roll back consistently across CSI and GitOps controllers.

Sequence stateful namespace moves independently:

1. Create destination namespace, policies, secrets, and service accounts.
2. Create and verify the new PVC from a tested backup or snapshot.
3. Quiesce the old writer.
4. Perform final synchronization and start the destination workload.
5. Validate application data, mounts, probes, and clients.
6. Retain the old PVC through an agreed rollback window.
7. Remove old resources only after explicit approval.

## Stop Conditions

Stop immediately when:

- a PVC UID or backing PV changes during an ownership-only migration;
- an Application scheduled for deletion still has a resources finalizer;
- two Applications report ownership of the same resource;
- a new pod is Pending because PV and pod node affinity no longer intersect;
- a backup or restored dataset cannot be validated;
- unrelated Git worktree changes appear during a migration phase.
