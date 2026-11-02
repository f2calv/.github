# Roots and Modules Reference

Establish the existing contract, lay out onion deployment roots and incubate, promote and integrate
child modules.

## Establishing the Existing Contract

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

## Onion Deployment Roots

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

## Local Child Modules

Reusable child modules may stay in the main repository's `modules/` folder during early use.
Private or application-specific modules may remain local indefinitely. Neither the folder name nor
the presence of one consumer requires a separate repository.

Keep the boundary clean even before promotion: typed inputs and outputs, caller-owned providers
and state, explicit dependencies, tags and no embedded deployment coordinates.
Extract a coherent capability, not every individual resource mechanically.

## Promotion Criteria

Promote a module to its own repository when it is battle-tested and reliable, its contract is
stable enough to version independently, and independent reuse/release ownership justifies the
overhead. Evidence should include successful operation and upgrades, relevant failure or
replacement behavior, useful validation and a documented consumer contract. A passing
`terraform validate` alone is not maturity. Do not invent a fixed consumer count or deployment
count as the promotion threshold.

For confidential implementations, choose a private module repository or keep the module local;
promotion is not authorization to publish. Review the interface, examples and history before
making reusable infrastructure public.

## Promotion Procedure

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

## Local-First Integration Before Publication

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

## Public Exemplars

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
