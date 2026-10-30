---
name: iac-terraform
description: 'Create, extend, audit, refactor or retire Terraform IaC repositories: onion-layered deployment roots, lifecycle and state boundaries, local/private child modules, promotion to external module-per-repository releases, provider wiring, cost controls and safe deployment sequencing.'
---

# Terraform IaC

Build infrastructure repositories around explicit ownership, lifecycle and state boundaries.
Keep independently applied deployment roots separate from reusable child modules, even when
both live beneath a directory named `modules`.

## Authorities And Boundaries

- The [Terraform instructions](../../instructions/iac.terraform.instructions.md) own HCL style,
  provider/version constraints, state handling, address migrations and release conventions.
  This skill owns repository construction, composition and the operational workflow.
- Use [repository baseline](../repository-baseline/SKILL.md) and
  [Dependabot management](../dependabot-management/SKILL.md) for repository settings and dependency
  coverage, and [README authoring](../docs-readme/SKILL.md) for consumer documentation.
- Use [GitOps repository structure](../gitops-repository-structure/SKILL.md) for Argo CD ownership
  and workload cleanup, not Terraform as a second owner of the same Kubernetes resources.
- Check [repository privacy](../repository-privacy/SKILL.md) before public content. Generalize
  private implementation evidence; never publish its names, coordinates or topology.

HashiCorp recommends
[flat module composition and dependency inversion](https://developer.hashicorp.com/terraform/language/modules/develop/composition),
[caller-owned provider configuration](https://developer.hashicorp.com/terraform/language/modules/develop/providers)
and a [standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure).
The numbered onion layout and `src/` placement below are repository conventions, not Terraform
requirements. Do not impose a large hierarchy on a repository that needs only one deployment root.

## Modes And Safety

| Mode | Outcome |
| --- | --- |
| Design/bootstrap | Agree boundaries and construct the requested repository configuration |
| Evolve | Change existing roots/modules without changing unrelated ownership or state |
| Audit | Report evidence, risks and ordered corrections without editing or deploying |
| Retire | Remove approved infrastructure in reverse dependency order and verify residual resources |

Configuration work does not authorize cloud access, deployment, publication or tests.
Follow the Terraform instructions' approval gates for remote state, plans and mutations.
Keep plans/state private; a saved plan can contain sensitive values even when terminal output is
redacted. Ask before tests, including `terraform test` and provider-backed examples.

## 1. Establish The Existing Contract

1. Resolve the requested repositories, working trees, instructions, audience and deployment target.
   Inspect current automation and representative roots/modules before selecting a layout.
2. Catalogue independently applied roots: backend/key, owner, provider aliases, target selectors,
   resource/data ownership, dependencies and normal change cadence. Read only needed state
   metadata after approval; never dump state or credentials into a report.
3. Identify what runs outside Terraform: bootstrap, GitOps, migrations, identity registration,
   manual import and restore procedures. A README or declared output is not deployment evidence.
4. Separate naming dimensions from lifecycle boundaries. Two subscriptions are not automatically
   two environments; environments are not automatically separate repositories. Ask when durable
   data ownership, trust boundaries or the target account are genuinely ambiguous.
5. Search existing shared modules before writing another implementation. Verify their actual
   input/output contract and pinned release rather than relying on a repository name.

## 2. Design The Onion As Deployment Roots

An onion protects the most stable infrastructure from routine application changes:

| Example root | Ownership and lifecycle |
| --- | --- |
| `0core` | Foundational groups, secret/state stores and long-lived platform dependencies |
| `1resources` | Compute and managed application-service infrastructure |
| `2services` | Cluster/provider-dependent services and faster-changing integrations |
| Later roots | Separate monitoring or operational concerns only when lifecycle warrants it |
| Independent roots | Ancillary systems with genuinely separate ownership, state or retirement |

These names are illustrative; preserve an existing repository's state keys and layer names.
Use cadence as a heuristic, not a fixed schedule. Put a resource in the lowest layer that should
own its lifecycle, not in the foundation merely because several applications use it.

An established layout can keep both kinds of module under one parent:

```text
src/terraform/
  modules/
    0core/             # Deployment root: its own backend, providers and state
    1resources/        # Deployment root: a separate apply boundary
    2services/         # Deployment root: depends on a reachable provisioned service
    example_service/   # Local child module: no backend or provider configuration
```

- **The onion layers stay in the main IaC repository.** They compose account-specific
  infrastructure and are not candidates for extraction into reusable module repositories.
- Give each deployment root separate remote state and locking. Keep its backend key stable;
  moving a folder must not silently select empty state.
- Make dependencies explicit through provider data lookups and caller-owned inputs. Follow the
  existing cross-root contract; do not expose another root's whole state as a shortcut.
- Prefer shallow composition. A root wires coherent child capabilities; it should not need a deep
  chain of pass-through wrappers.
- Document apply order separately from the resource/module dependency graph. Directory numbering
  does not orchestrate Terraform, and `depends_on` cannot order separate root executions.

## 3. Incubate Children Locally; Promote Proven Capabilities

Reusable child modules may stay in the main repository's `modules/` folder during early use.
Private or application-specific modules may remain local indefinitely. Neither the folder name nor
the presence of one consumer requires a separate repository.

Keep the boundary clean even before promotion: typed inputs and outputs, caller-owned providers
and state, explicit dependencies, tags and no embedded deployment coordinates.
Extract a coherent capability, not every individual resource mechanically.

Promote a module to its own repository when it is battle-tested and reliable, its contract is
stable enough to version independently, and independent reuse/release ownership justifies the
overhead. Evidence should include successful operation and upgrades, relevant failure or
replacement behavior, useful validation and a documented consumer contract. A passing
`terraform validate` alone is not maturity. Do not invent a fixed consumer count or deployment
count as the promotion threshold.

For confidential implementations, choose a private module repository or keep the module local;
promotion is not authorization to publish. Review the interface, examples and history before
making reusable infrastructure public.

### Promotion Procedure

1. Separate generic mechanics from root-owned policy, resource names, account selection and
   operational credentials. Keep shared dependencies caller-owned rather than recreating them.
2. Create one repository per coherent reusable module, with code under `src/`, root consumer
   documentation, license where appropriate, existing lint/validation tooling and release policy.
   The child declares requirements but no backend or configured providers.
3. Prove the interface and representative supported configurations without live credentials where
   possible. Obtain separate approval for cloud examples and destructive/replacement scenarios.
4. Publish an immutable module release only when authorized. Follow the existing versioning and
   migration rules rather than inventing a compatibility layer.
5. Change the root's local source to the released external source. Preserve the module call label
   and internal resource addresses where possible; use reviewed address migrations when necessary.
   Changing source location alone does not require recreating infrastructure.
6. Inspect the caller's saved plan. Reject unintended replacements and verify the resulting
   module source before removing the local implementation.

Example source shape, using synthetic coordinates and a release that the caller must verify:

```hcl
source = "git::https://github.com/owner/tf_module_example.git//src?ref=1.2.3"
```

Git source strings are literals. Use the Terraform instructions' local override workflow for
adjacent-checkout integration; do not replace tracked immutable refs with working branches.

### Offer Local-First Integration Before Publication

When evolving a shared child module, offer the user a choice before proposing its remote PR or
release: validate and deploy the consuming root with adjacent local module files first, or use
the remote PR/release path first. Recommend local-first when the checkouts are available so missing
inputs, outputs, permissions and provider behavior can be found before publication. Do not make
publishing a module a prerequisite for testing it in its real caller.

- Use the root repository's gitignored source-override workflow, preserve tracked immutable refs,
  and verify the resolved module source before planning. Record the local module revision and
  uncommitted-change status alongside the deployment evidence.
- Local integration is not blanket authorization for tests or cloud access. Obtain those approvals
  separately, review a saved plan and apply that exact artifact under the normal deployment gates.
  Verify the intended resources and consumer access; empty collections do not prove the lifecycle
  of resource types that were never exercised.
- Keep commits, pushes, PRs and releases behind their own authorization. After local verification,
  publish the tested module through its normal process, pin the resulting immutable release in the
  caller, remove the override and check the released source converges before declaring it portable.

## 4. Wire Every Consumer Surface

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

## 5. Plan And Apply By Ownership Boundary

1. Run formatting, backend-free initialization where needed and validation with the pinned tools.
   Use existing tests after approval; distinguish static validation, mocked plans and live checks.
   Verify that the intended cases actually ran: an unknown test-file filter can exit zero with
   no tests. Match platform-native test paths and reject zero-case success or filter warnings.
2. Obtain permission for the exact cloud/state scope. Confirm the account and existing backend,
   then generate a saved plan for the smallest affected root.
3. Review creates, updates, replacements and destroys individually, including nested modules and
   role assignments. Distinguish harmless deployment-tag updates from functional drift; do not
   accept unrelated changes because the plan is otherwise plausible.
4. Apply only the inspected plan after approval, in dependency order. Do not dispatch paid remote
   workflows merely to substitute for a local read or review.
5. Verify actual resources and consumer access, not only Terraform's exit code. Re-plan for
   convergence using the same deployment metadata; explain expected metadata-only changes if the
   source revision changes. A zero-resource validation run is not runtime evidence.

After a partial apply, inspect what actually succeeded before retrying. Some cloud APIs return
deletion success before a service name is reusable: check completion/availability, use bounded
backoff, and generate a new reviewed plan for the remaining approved actions. Do not reuse the
stale plan, rename the service silently, or roll back successful unrelated operations.

Successful role-assignment creation and dependency ordering do not prove service-side destination
authorization. Check the actual principal, permissions, scope and network before blaming propagation.
If an unchanged retry still fails after a reasonable propagation window, stop repeating it, preserve
partial-state evidence and investigate a different hypothesis. Broader scopes, additional privileges
and temporary diagnostic resources require explicit approval, not an automatic recovery fallback.

## 6. Retire In Reverse Order

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

For cost investigations, separate capacity/idle charges from transaction or premium-feature
meters. Compare billing dates, currency and tax basis, and report diagnostic gaps. Resource-level
cost is not proof of which application called it, and missing metrics are not zero activity.

## Evidence And Public Examples

These public modules illustrate current repository conventions, not an endorsement of every
setting or a requirement to copy implementation-specific behavior:

- [App Service module usage](https://github.com/f2calv/tf_module_azurerm_app_service_plan/blob/main/README.md#usage)
  and [provider requirements](https://github.com/f2calv/tf_module_azurerm_app_service_plan/blob/main/src/versions.tf).
- [Storage module interface](https://github.com/f2calv/tf_module_azurerm_storage_account/blob/main/src/variables.tf)
  and [implementation](https://github.com/f2calv/tf_module_azurerm_storage_account/blob/main/src/main.tf).
- [Cluster module usage](https://github.com/f2calv/tf_module_azurerm_kubernetes_cluster/blob/main/README.md#usage).

They demonstrate `src/` modules, caller-owned providers/state, typed interfaces, immutable source
examples and independent releases. Do not generalize workstation-mutating provisioners,
unnecessary credential outputs or dynamic latest-version selection into new module defaults.

## Completion Report

Report roots/modules changed, evidence and unresolved decisions, the exact validation performed,
and whether work is only saved, committed, published or deployed. For deployment/retirement,
include verified live outcomes, remaining costs/dependencies and any rollback or restore limits.
Do not mark an ADR prerequisite complete from configuration or a staged file alone.

## Maintaining This Skill

- HashiCorp module/provider composition guidance, source syntax and state-migration behavior.
- The distinction between deployment roots and incubating/promoted child modules.
- Public exemplar source paths, release workflows and demonstrated interfaces.
- Cloud SKU replacement semantics, provider-dependent teardown and residual billing behavior.
- Local/CI tool parity, credential-free validation and approval boundaries.
