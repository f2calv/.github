# Audit and Validation Reference

Report conformance findings, automate structural guardrails and verify every migration phase.

## Conformance Audit

Use `scope=audit` before adding a major workload, after changing bootstrap discovery, and
periodically for every managed cluster.

Report:

1. each root and the exact path it discovers;
2. any discovered non-Application document;
3. wrapper Applications and the boundary each one adds;
4. duplicate, overlapping, or ambiguous resource ownership;
5. Applications still using `default` or an over-broad AppProject;
6. AppProject source, destination, namespaced-kind, and cluster-kind grants;
7. broad category/environment namespaces containing unrelated owners;
8. Applications whose effective dependency order exists only on a wrapper;
9. namespace-qualified service addresses, namespace-local Secrets/ConfigMaps/RBAC, and other move
   blockers;
10. stateful workloads without a current inventory and proven restore path.

Classify findings:

| Priority | Meaning |
| --- | --- |
| Blocker | Discovery can apply the wrong document, pruning/ownership is unsafe, or persistent data lacks a recoverable path |
| High | AppProject or namespace permissions cross unrelated trust boundaries |
| Medium | Wrapper, wave, naming, or source layout creates avoidable operational coupling |
| Low | Structure is safe but inconsistent or unnecessarily difficult to navigate |

Recommend the smallest ordered corrections. Put repository-only and stateless low-risk work first,
then ownership handoffs, policy tightening, stateless namespace moves, and finally independent
stateful data migrations. Never report directory tidiness alone as a security improvement.

## Automation Guardrails

Add repository validation that:

- enumerates every YAML document below each Applications-only tree and rejects kinds other than
  `Application` and `ApplicationSet`;
- rejects a root whose source includes its own manifest;
- detects duplicate Application names and obvious overlapping in-repository source ownership;
- renders or validates leaf sources with the repository's existing Helm, Kustomize, schema, and
  policy tooling;
- runs `git diff --check`.

Static validation cannot prove safe live ownership transfer, CRD readiness, project enforcement,
network connectivity, backup validity, or restore correctness. Keep those as explicit runtime
gates.

## Phase Validation

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
