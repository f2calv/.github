---
name: terraform-infrastructure
description: 'Create, extend, audit, refactor or retire Terraform IaC repositories: onion-layered deployment roots, lifecycle and state boundaries, local/private child modules, promotion to external module-per-repository releases, provider wiring, cost controls and safe deployment sequencing. Use when changing a Terraform repository''s structure, modules or deployment order; HCL style lives in the Terraform instructions.'
---

# Terraform IaC

Build infrastructure repositories around explicit ownership, lifecycle and state boundaries.
Keep independently applied deployment roots separate from reusable child modules, even when
both live beneath a directory named `modules`.

| Reference | Holds |
| --- | --- |
| [Roots and modules](references/roots-and-modules.md) | Contract discovery, onion layout, local children, promotion, local-first integration, exemplars |
| [Deployment and retirement](references/deployment-and-retirement.md) | Consumer wiring, plan/apply, partial-apply recovery, retirement, cost investigations |
| [Module releases](references/module-releases.md) | Child-module versioning directives, breaking changes and pull-request CI |

## Authorities And Boundaries

- The [Terraform instructions](../../instructions/iac.terraform.instructions.md) own HCL style,
  provider/version constraints, state handling, address migrations and release conventions.
  This skill owns repository construction, composition and the operational workflow.
- Use [repository baseline](../github-repository-baseline/SKILL.md) and
  [Dependabot management](../github-dependabot/SKILL.md) for repository settings and dependency
  coverage, and [README authoring](../docs-readme/SKILL.md) for consumer documentation.
- Use [GitOps repository structure](../gitops-repository-structure/SKILL.md) for Argo CD ownership
  and workload cleanup, not Terraform as a second owner of the same Kubernetes resources.
- Check [repository privacy](../repository-privacy/SKILL.md) before public content. Generalize
  private implementation evidence; never publish its names, coordinates or topology.

HashiCorp recommends
[flat module composition and dependency inversion](https://developer.hashicorp.com/terraform/language/modules/develop/composition),
[caller-owned provider configuration](https://developer.hashicorp.com/terraform/language/modules/develop/providers)
and a [standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure).
The numbered onion layout and `src/` placement are repository conventions, not Terraform
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

- Inspect automation and representative roots/modules, catalogue every independently applied root,
  and identify what runs outside Terraform before selecting a layout
  ([contract](references/roots-and-modules.md#establishing-the-existing-contract)).
- Read only needed state metadata after approval; never dump state or credentials into a report.
- Separate naming dimensions from lifecycle boundaries, and search existing shared modules first.

## 2. Design The Onion As Deployment Roots

- Put a resource in the lowest layer that should own its lifecycle; preserve existing state keys
  and layer names ([onion](references/roots-and-modules.md#onion-deployment-roots)).
- Onion layers stay in the main IaC repository. Each root has separate remote state and locking
  with a stable backend key.
- Directory numbering does not orchestrate Terraform; document apply order separately.

## 3. Incubate Children Locally; Promote Proven Capabilities

- Child modules may stay local; keep their boundary clean before promotion
  ([local children](references/roots-and-modules.md#local-child-modules)).
- Promote only battle-tested capabilities with a stable contract, never as authorization to publish
  ([criteria](references/roots-and-modules.md#promotion-criteria),
  [procedure](references/roots-and-modules.md#promotion-procedure)).
- Offer local-first integration before a module PR or release
  ([local-first](references/roots-and-modules.md#local-first-integration-before-publication)).

## 4. Wire Every Consumer Surface

- Forward new settings through every root, module, output, example and doc surface; verify
  data-plane authentication and SKU/feature combinations separately
  ([wiring](references/deployment-and-retirement.md#consumer-surface-wiring)).
- Keep local and CI deployment paths aligned; do not create an unapproved clean clone or worktree.

## 5. Plan And Apply By Ownership Boundary

- Validate with pinned tools, then apply only an inspected saved plan for the smallest affected root
  after approval ([plan and apply](references/deployment-and-retirement.md#plan-and-apply)).
- Verify actual resources and consumer access, then re-plan for convergence.
- After a partial apply, inspect what succeeded and generate a new plan; never reuse a stale one
  ([recovery](references/deployment-and-retirement.md#partial-apply-recovery)).

## 6. Retire In Reverse Order

- Agree the intended outcome and obtain explicit deletion/data-loss approval
  ([retirement](references/deployment-and-retirement.md#retirement)).
- Remove workloads and cluster-dependent resources before their cluster; never run a whole-root
  `destroy` that removes unrelated services.
- Verify residual chargeable resources and convergence of former dependents
  ([cost](references/deployment-and-retirement.md#cost-investigations)).

## Completion Report

Report roots/modules changed, evidence and unresolved decisions, the exact validation performed,
and whether work is only saved, committed, published or deployed. For deployment/retirement,
include verified live outcomes, remaining costs/dependencies and any rollback or restore limits.
Do not mark an ADR prerequisite complete from configuration or a staged file alone.

## Maintaining This Skill

- HashiCorp module/provider composition guidance, source syntax and state-migration behavior.
- The distinction between deployment roots and incubating/promoted child modules.
- Public exemplar source paths, release workflows and demonstrated interfaces in the roots and
  modules reference.
- Cloud SKU replacement semantics, provider-dependent teardown and residual billing behavior.
- Local/CI tool parity, credential-free validation and approval boundaries.
