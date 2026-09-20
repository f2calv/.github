---
description: 'Terraform authoring conventions — formatting, versions, layout, variables, resources, outputs, security, and the split between reusable child modules and root modules.'
applyTo: '**/*.tf,**/*.tfvars,**/*.hcl'
---

# Terraform

This file covers how to write the HCL. Repository-specific topology, variable bootstrap, state coordinates and deployment workflow belong in that repository's `.github/copilot-instructions.md`, not here.

Two role-specific sections follow the universal rules. Apply exactly one of them:

- **Reusable child module repository** — publishes a module consumed by someone else's root module. It declares no backend, no provider configuration and no state of its own.
- **Root module repository** — the configuration actually applied against a cloud subscription. It owns the backend, the provider configuration and the state.

## Running Terraform

- `terraform fmt`, `terraform validate` and a backend-free `terraform init` are safe to run unprompted; none of them authenticate or touch state.
- Always ask before any command that authenticates to the cloud provider, reads remote state or mutates infrastructure — `plan`, `apply`, `destroy`, `import` and `state` subcommands included.
- For an approved apply, save the plan to a file, inspect its exact create/update/replace/destroy actions, and apply that same plan artifact. Do not review one plan and then apply a newly calculated plan.
- After an address migration, provider transition or other state-sensitive refactor, run a second plan and require a no-change result before removing migration scaffolding.
- Where the host has no linters installed, run `tflint` and `trivy` from their official containers, and `markdownlint` through `npx`, rather than installing them.

## Formatting

- Run `terraform fmt -recursive` before every commit. All `.tf`, `.tfvars` and `.hcl` files must pass with no changes.
- 2-space indentation, Terraform's default. Let `fmt` handle argument alignment; never hand-align.
- Use `#` for comments. Avoid `//` — `fmt` leaves it untouched, so it drifts from the rest of the file.

## File Conventions

| File | Purpose |
| --- | --- |
| `main.tf` | Resource, `data` and `module` blocks |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output values |
| `versions.tf` | `terraform {}` block with `required_version` and `required_providers` |
| `providers.tf` | Root module only — backend, provider configuration and shared `data` lookups |
| `imports.tf` | Root module only — one-time `import` blocks, deleted after the first successful apply |

- `providers.tf` is the right home for `data` sources that many resources consume. A `data` block used by a single resource belongs beside its consumer in `main.tf`.
- `README.md` documents usage, every variable and every output. Update it in the same commit as any interface change.

## Versions

- Every entry in `required_providers` declares an explicit `source`. Never rely on implicit namespace resolution.
- Pin the `version` on every `helm_release`. A floating chart version turns an unrelated apply into an unplanned upgrade.
- Version pinning strategy differs by role — see the two role sections below.

## Variables

- Every variable declares a `type`.
- Declare a `description` stating what the value *is*, in one line. A child module describes every variable without exception; a root module may omit it only for self-evident shared plumbing inputs.
- Names are `snake_case` and descriptive, prefixed by domain when ambiguous.
- Give a `default` only where a sensible one exists. A value the caller must own — a name, a parent resource id — stays required.
- Prefer a `map(string)` or `map(object({...}))` over parallel lists so `for_each` keys stay stable and readable.
- Keep deployment policy and frequently tuned values in the root's variable source: account names, regions, SKUs, capacities, budgets, alert thresholds and runtime limits. `main.tf` should wire resources and modules, not bury environment-specific policy in literals.
- For complex object inputs, use `optional(type, default)` for knobs with a safe, broadly useful default. Keep only values with no defensible default required, such as globally unique names, parent ids and model versions.
- Model repeated regional or service variants as a `map(object({...}))` and flatten nested maps into stable composite `for_each` keys. Do not grow a reusable module by adding one resource block and one input family per named variant.
- Group related variables under a section-separator comment:

  ```hcl
  # ── Section ──────────────────────────────────────────────────────────────────
  variable "example_name" {
    type        = string
    description = "Name of the example resource."
  }
  ```

## Resources and Data Sources

- **Name the primary resource `this`.** Secondary resources take a descriptive suffix, such as `this_pv` or `this_secret`.
- **Registry comment-link above each resource block**, pointing at the provider documentation for that resource type:

  ```hcl
  # https://registry.terraform.io/providers/<namespace>/<provider>/latest/docs/resources/<resource_type>
  resource "<provider>_<resource_type>" "this" {
  ```

- **`data` sources for anything managed elsewhere.** A resource owned by another state, another subscription, or created by hand is referenced through a `data` lookup, never a hardcoded resource id.
- **`for_each` over `count`.** Use `for_each` with a map for any multi-instance resource; it produces stable, readable state keys. Reserve `count` for the boolean on/off idiom, `count = var.feature_enabled ? 1 : 0`.
- **Explicit `depends_on`** wherever the dependency is not already expressed by an attribute reference.
- **Tags**: every taggable resource sets the shared tags variable, merged with resource-specific tags where needed.

## Outputs

- Every output declares a `description`.
- Mark every key, password, connection string and certificate output `sensitive = true`.
- Source an output from the resource that owns it, so the value is not silently echoing an input back to the caller.

## Naming

- **Terraform identifiers**: `snake_case`, prefixed by resource group or domain. Module labels follow the same rule.
- **Cloud resource names**: composed from a variable plus the environment suffix, `"${var.base_name}${var.env}"`, so one definition yields distinct names per environment. Never hardcode an environment into a name. Keep base names short and lowercase with no redundant prefixes.

## Security

- **No secrets in configuration.** Never hardcode a key, connection string or credential, and never give a variable a secret default.
- **Secrets resolve at plan time** from the platform secret store through a `data` lookup.
- **Sensitive outputs** are marked `sensitive = true` so they are redacted from plan output and CI logs.
- **Least privilege** for every access policy and role assignment, declared alongside the resource it protects rather than granted ad hoc. Drive role assignments from a descriptive `{ role, scope }` map rather than scattering individual assignment blocks.
- **State contains secrets.** Terraform writes resolved secret values and output values into state, so treat the state backend as a secret store: keep it private, keep it out of any repository, and never paste raw plan or state output into an issue or pull request.
- Never commit a real subscription, tenant, object or resource identifier, hostname, IP address or account name. Use placeholders such as `00000000-0000-0000-0000-000000000000` and `example.com`.

## Provisioners

`null_resource` with `local-exec` is a last resort for steps with no provider coverage. Where one is unavoidable:

- Set an explicit `interpreter` — `["pwsh", "-Command"]` or `["/bin/bash", "-c"]` — rather than relying on the host default.
- Set `when = create` or `when = destroy` explicitly.
- Give `triggers` a meaningful value. `build_number = timestamp()` means "re-run on every apply": use it deliberately and comment why.
- Add `depends_on` for the resource the script actually targets.

## Forward-Only Maintenance

- Maintain only the current supported interface. Deprecated or retired provider arguments, outputs, SKUs, APIs and platform features have no place in the configuration.
- Remove obsolete inputs and outputs instead of retaining aliases, compatibility shims or no-op variables.
- Prefer a clean breaking release over preserving outdated behaviour.
- When an upstream platform announces retirement, adapt before the retirement date and remove the retired option.

## Dead Code

Commented-out blocks accumulate fast in Terraform. Delete superseded and dormant configuration outright; Git holds the history. Where a block is intentionally dormant rather than dead, keep it commented but prefix it with a one-line reason and, where known, the condition for re-enabling it.

## Reusable Child Module Repositories

Applies when the repository publishes a module for other root modules to consume over a pinned source.

### Versions and Providers

- Set `required_version` to the oldest Terraform the module's syntax needs. Constrain each provider to the current supported major with a permissive lower and exclusive upper bound, such as `>= 5.0, < 6.0`.
- **Never pin an exact version.** A child module pinning `= 4.81.0` cannot be composed with a caller or a sibling module that needs anything else. Exact pins belong to the root module.
- **Do not declare `provider` blocks.** Providers are inherited from the caller, which may pass a specific alias via `providers = { ... }`. Pass an alias onto an individual block with `provider = <name>.<alias>`.
- **Do not declare a `backend`.** The caller owns state.
- **Do not commit `.terraform.lock.hcl`.** A child module must not pin the caller's provider build.

### Interface

- Keep the module focused on a single resource type or a tightly coupled group, and expose all customisation through variables.
- Prefer a generic map input and map outputs when a module owns several instances of the same resource type. Callers should add an instance as data, without requiring another resource block or output pair in the module.
- **Accept ids rather than creating shared dependencies.** A resource that could reasonably be shared by several callers — a workspace, a resource group, a virtual network — is passed in by id, not created here. Creating it inside the module hands its lifecycle to whichever caller instantiated the module first.
- **No `lifecycle { prevent_destroy = true }`.** It is the caller's decision and, once published, it blocks a `terraform destroy` the caller may legitimately want.
- Keep the sensitive surface minimal — expose an id or an endpoint rather than a raw key wherever the caller can look the secret up itself.

### Module Versioning

- Continuous integration bumps the patch version on every pull request, so a `+semver:` directive is only needed to request a larger increment than a patch.
- Before adding a `+semver:` directive, inspect every commit between the merge base with `origin/main` and `HEAD`. A branch must contain at most one directive, placed in the commit that introduces the versioned behaviour.
- Use `+semver:feature` for breaking changes, including removed or renamed inputs, outputs and resource addresses. A compatible change needs no directive.
- After the branch is complete, run GitVersion with the repository's `GitVersion.yml` and verify the final numeric major, minor and patch result.
- Publish releases as plain `X.Y.Z` tags with no prefix and no moving aliases, per `github.instructions.md`, and set the release-versioning workflow inputs accordingly.
- Pin the module source example in `README.md` to the expected final immutable tag, excluding feature-branch pre-release labels, and update it in the same change. Treat a mismatch between the README source ref and the expected release tag as a CI failure.

### Breaking Changes

Adding a required variable, renaming a resource, or removing a resource is a breaking change for every consumer.

- Publish breaking changes as a new major release without in-module compatibility shims. Consumers migrate explicitly when they update their pinned tag.
- Document any state migration command consumers must run before applying the new major release.
- Require callers to pin to a tag. A caller tracking a branch ref inherits breaking changes silently on their next `init`.
- Record the change in the commit message with a `BREAKING CHANGE:` footer.

### Continuous Integration

- Pull requests must run `terraform fmt`, a backend-free `terraform init` and `terraform validate`, and all three must pass without cloud credentials. With no backend declared, `-backend=false` is sufficient.
- Require the validate job as a status check on `main`, alongside the repository-wide lint and versioning checks.
- Configure Dependabot's `terraform` ecosystem for the module directory, keep provider ranges broad within the current supported major, and validate automated provider-major updates through the same pull request checks as manually authored changes.

## Root Module Repositories

Applies when the repository holds the configuration applied against a cloud subscription.

### Versions and Providers

- **Terraform**: pin to an exact version in `required_version`, identical across every module in the repository.
- **Providers**: use a pessimistic constraint (`~>`) on major.minor for mainstream providers, and an exact pin (`=`) where a patch bump has previously broken a plan.
- **Commit `.terraform.lock.hcl`.** The root module owns the resolved provider builds, and the lock file is what makes a plan reproducible.
- Declare provider configuration here. Where the configuration spans more than one subscription or cluster, declare aliased providers and pass them explicitly with `providers = { ... }` on a module call or `provider = <name>.<alias>` on a block.

### Backend and State

- Declare the `backend` as a **partial configuration** and supply the coordinates through `terraform init -backend-config=...` or environment variables, so the same configuration can target more than one environment without editing tracked files.
- Never commit backend coordinates, account names or state keys to a public file.
- A state key binds a configuration to its existing state — treat it as immutable once applied.
- Re-run `terraform init` after switching target environment when the backend coordinates differ.
- Cross-configuration references go through `data` sources, never through hardcoded ids.

### State Refactors

- Use `moved` blocks when renaming resources, adding `for_each`, changing module labels or otherwise changing Terraform addresses. Do not accept destroy-and-recreate actions that exist only because configuration structure changed.
- Before removing or renaming a provider alias, check whether state objects still reference its provider address. Keep the old alias temporarily, targeting the same immutable subscription or project, until those objects have been moved or destroyed and a subsequent plan succeeds without it.
- A root module may remove one-time `moved` blocks after every state it owns has applied the migration and a no-change plan passes. A published reusable module retains `moved` blocks for supported upgrade paths because consumers migrate on different schedules.
- Verify platform availability for region-bound services, SKUs and models against the live provider or cloud API before applying. Documentation can describe general availability while the target account, subscription or region still rejects a deployment.

### Stateful Resources

- **`lifecycle { prevent_destroy = true }`** on every stateful resource — resource groups, secret stores, storage accounts, databases and log workspaces. Put the `lifecycle` block first in the resource body so it cannot be missed during review.

### Module References

- Reference a sibling module by relative path; reference an external module by a pinned Git source ref.
- Terraform module `source` values must be literals during `terraform init`; do not attempt to parameterize a repository root, branch or local path through an input variable.
- Keep tracked external-module sources pinned to immutable release tags. Do not commit a feature-branch ref to make local integration testing work.
- For local integration against an adjacent module checkout, add a gitignored `source_override.tf` in the root module and override only the affected module block with a relative local path. Re-run `terraform init -upgrade` after adding, changing or removing the override, and inspect `.terraform/modules/modules.json` when source provenance matters.

### Kubernetes and Helm Providers

- Configure the `kubernetes`, `helm` and `kubectl` providers from a cluster `data` lookup rather than an ambient kubeconfig, so a plan is reproducible on any machine.
- Pass Helm values through `templatefile()` with an explicit variable map instead of inline `set` blocks.
- Keep two values files per chart:
  - `<chart>-values-<version>.yml` — the unmodified upstream values file for that exact chart version, kept purely as a diffing reference and never consumed by Terraform.
  - `<chart>-values.yaml` — the trimmed override set actually passed to `templatefile()`, opening with a link to the upstream file and a note that `${...}` placeholders are present.
- When bumping a chart version, replace the reference file and re-diff the override file in the same commit.

### Importing Existing Resources

- Use Terraform 1.5+ `import` blocks in an `imports.tf` file, not `terraform import` CLI commands.
- Map each existing resource to its full address, including the `for_each` key where applicable.
- Head the file with a comment stating it should be deleted after the first successful `apply`.
- Retrieve real resource ids with a cloud CLI query before writing the blocks. Never guess an id's shape.
