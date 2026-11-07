# Deployment and Retirement Reference

Wire every consumer surface, plan and apply by ownership boundary, recover partial applies and
retire infrastructure in reverse order.

## Consumer Surface Wiring

- Root inputs and deployment-variable sources must expose the intended policy. Forward new
  settings through root object types, module calls, child inputs, outputs, examples and docs.
  A child default hidden behind a conflicting root default is not an effective default.
- Keep required identity/naming inputs distinct from optional operational settings. Do not grow
  a generic module with application-specific flags for every caller.
- Verify the deployment provider's data-plane authentication separately from portal OAuth
  defaults and runtime identity grants. A keyless account also needs provider Entra configuration,
  endpoint connectivity and permissions for every lifecycle operation, including ACL reads/writes.
- Verify SKU/feature combinations against the pinned provider and actual cloud API. Omit
  unsupported arguments/blocks, reject incompatible explicit settings, and document nullable
  outputs when a feature has no identity or endpoint. A cheaper tier may require replacement,
  not an in-place resize.
- For optional infrastructure, gate both resources and their data/provider dependencies. Preserve
  a separate transitional connection path when existing resources still need destruction.
- Review workflow selectors, provider aliases, bootstrap, documentation and runtime consumers.
  A false flag or zero count is not proof that providers stop querying an absent cluster.
- Keep local and CI deployment paths aligned on source, tool versions, variables and backend.
  Do not create a clean clone or worktree as an unapproved workaround.

## Plan and Apply

1. Run formatting, backend-free initialization where needed and validation with the pinned tools.
   Use existing tests after approval; distinguish static validation, mocked plans and live checks.
   Verify that the intended cases actually ran: an unknown test-file filter can exit zero with
   no tests. Match platform-native test paths and reject zero-case success or filter warnings.
   A `.terraform` folder created inside a Dev Container can hold provider symlinks into its plugin
   cache, so host `init` fails with "cannot install package into target directory ... because it is
   a symlink". Remove only the confirmed stale provider-cache entries and initialize again; keep
   the lock file, backend metadata and workspace selection. If the entire `.terraform` folder
   must be rebuilt, first record the backend initialization arguments and selected workspace,
   then restore both and verify `terraform workspace show` before planning or applying.
2. Obtain permission for the exact cloud/state scope. Confirm the account and existing backend.
   Before cloud-backed initialization, verify that both the target and the state-backend
   subscriptions are enabled; a disabled backend can block even the storage-key lookup. An
   `Enabled` status alone does not prove readiness: if an operation still returns
   `ReadOnlyDisabledSubscription`, keep that root blocked and record the contradiction rather than
   changing authentication or state ownership to bypass it. Then generate a saved plan for the
   smallest affected root.
3. Review creates, updates, replacements and destroys individually, including nested modules and
   role assignments. Distinguish harmless deployment-tag updates from functional drift; do not
   accept unrelated changes because the plan is otherwise plausible.
4. Apply only the inspected plan after approval, in dependency order. Do not dispatch paid remote
   workflows merely to substitute for a local read or review.
5. Verify actual resources and consumer access, not only Terraform's exit code. Re-plan for
   convergence using the same deployment metadata; explain expected metadata-only changes if the
   source revision changes. A zero-resource validation run is not runtime evidence.

## Partial Apply Recovery

After a partial apply, inspect what actually succeeded before retrying, at each attempted
resource's exact cloud ID as well as in state. A timed-out create can complete remotely without
entering state: verify its identity and configured properties, then obtain approval to import only
matching untracked successes into their intended addresses; never recreate or blindly adopt them.
Some cloud APIs return deletion success before a service name is reusable: check completion/availability, use bounded
backoff, and generate a new reviewed plan for the remaining approved actions. Do not reuse the
stale plan, rename the service silently, or roll back successful unrelated operations.

Successful role-assignment creation and dependency ordering do not prove service-side destination
authorization. Check the actual principal, permissions, scope and network before blaming propagation.
If an unchanged retry still fails after a reasonable propagation window, stop repeating it, preserve
partial-state evidence and investigate a different hypothesis. Broader scopes, additional privileges
and temporary diagnostic resources require explicit approval, not an automatic recovery fallback.

## Retirement

Stopping, disabling, scaling to zero and deleting have different durability, availability and
billing effects. Agree which outcome is intended, what state may be lost, and what must survive.

1. Inventory active consumers, data, backups, public endpoints and every owner. Obtain explicit
   deletion/data-loss approval; do not assume a development label means disposable.
2. Reconcile GitOps/workload removal while the target is reachable. Verify finalizers complete
   before removing cluster registration; preserve unrelated cluster targets and shared templates.
   A deliberately dormant target may remain commented with its reason and re-enable conditions.
3. Remove cluster-dependent Helm/Kubernetes resources before their cluster. Keep provider
   connection data and any state-referenced aliases until cleanup finishes.
4. Apply the underlying root's approved disablement, not a whole-root `destroy` that would also
   remove unrelated managed services. Preserve stateful resources outside the retirement scope.
5. Verify residual disks, load balancers, public IPs, gateways, private endpoints and other
   chargeable resources. A stopped VM or deleted workload does not imply zero ongoing cost.
6. Check both the retired root and its former dependents converge without querying absent
   infrastructure. Future clusters need new registration, credentials and destination review;
   retained templates are reusable, old connection details are not.

## Cost Investigations

Separate capacity/idle charges from transaction or premium-feature meters. Compare billing dates,
currency and tax basis, and report diagnostic gaps. Resource-level cost is not proof of which
application called it, and missing metrics are not zero activity.
