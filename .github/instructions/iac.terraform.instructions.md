---
description: 'Terraform authoring conventions — formatting, versions, layout, variables, resources, outputs, security, and the split between reusable child modules and root modules.'
applyTo: '**/*.tf,**/*.tfvars,**/*.hcl'
---

# Terraform

How to write the HCL. The [Terraform IaC skill](../skills/terraform-infrastructure/SKILL.md) owns
repository construction, onion-layered roots, module promotion and provisioning order, and its
[conventions reference](../skills/terraform-infrastructure/references/terraform-conventions.md)
holds every rule below with its reasons. Repository topology, state coordinates and deployment
workflow belong in the repository's own instructions.

## Running Terraform

- `terraform fmt` and `terraform validate` are safe unprompted; initialise statically with
  `terraform init -backend=false` and a fresh `TF_DATA_DIR`.
- Ask before anything that authenticates, reads remote state or mutates infrastructure: `plan`,
  `apply`, `destroy`, `import` and `state`. Apply only the saved, reviewed plan file, and require a
  no-change plan after a state-sensitive refactor before removing migration scaffolding.

## Authoring

- `terraform fmt -recursive` before every commit; `#` comments; standard files (`main.tf`,
  `variables.tf`, `outputs.tf`, `versions.tf`, root-only `providers.tf` and `imports.tf`); the README
  documents every variable and output in the same commit.
- Every provider has an explicit `source`; every `helm_release` pins its chart `version`.
- Variables: a `type`, a one-line `description` (always in child modules), `snake_case` names,
  defaults only where defensible, maps over parallel lists, `optional()` for safe knobs, and
  deployment policy in variables rather than literals.
- Resources: the primary is `this`; a registry documentation link above each block; `data` lookups
  for anything managed elsewhere; `for_each` over `count` except the on/off idiom; explicit
  `depends_on` where no reference exists; shared tags on every taggable resource.
- Outputs declare a `description`, come from the owning resource, and are `sensitive` for keys,
  passwords, connection strings and certificates.
- Names: `snake_case` identifiers; cloud names composed as `"${var.base_name}${var.env}"`.

## Security

- No secrets in configuration or variable defaults; resolve them at plan time through `data`
  lookups. Treat state as a secret store and never paste raw plan or state output publicly.
- Least privilege, declared beside the protected resource from a `{ role, scope }` map.
- `null_resource` provisioners are a last resort with an explicit `interpreter`, `when`, meaningful
  `triggers` and `depends_on`. Delete dead blocks; a deliberately dormant one carries its reason.

## Module Roles

Apply exactly one:

- **Reusable child module**: oldest-viable `required_version`, provider ranges within the current
  major and never exact pins; no `provider` blocks, `backend`, lock file or
  `prevent_destroy`; accept shared dependencies by id; release as plain `X.Y.Z` tags, breaking
  changes as a new major, with fmt, backend-free init and validate in pull requests.
- **Root module**: exact `required_version`, `~>` providers (exact where a patch broke a plan), a
  committed lock file, provider configuration and a partial backend with uncommitted coordinates.
  Use `moved` blocks for address changes, `prevent_destroy` first in every stateful resource,
  literal pinned module sources (a gitignored `source_override.tf` for local integration),
  provider credentials from cluster `data` lookups, and `import` blocks in a temporary `imports.tf`.
