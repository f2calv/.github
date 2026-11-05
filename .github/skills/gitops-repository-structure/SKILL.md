---
name: gitops-repository-structure
description: 'Create, audit, align or migrate Argo CD App-of-Apps repositories with Applications-only discovery, scoped AppProjects, ownership-based namespaces and PVC-safe changes. Use when changing how Argo CD discovers, groups or namespaces Applications.'
argument-hint: '[repository=path] [scope={create|audit|align|plan|migrate}]'
---

# GitOps Repository Structure

Create, audit, align or migrate an Argo CD App-of-Apps repository without treating directory
neatness as a runtime boundary. Keep root discovery restricted to Argo Applications, use
AppProjects and namespaces as deliberate authorization boundaries, use sync waves for ordering, and
separate Application ownership changes from namespace and data migrations.

Use [gitops-helm-upgrade](../gitops-helm-upgrade/SKILL.md) for routine third-party chart upgrades
without changing discovery, ownership or namespaces.

The Kubernetes GitOps instructions (`.github/instructions/kubernetes.gitops.instructions.md`) own the baseline layout,
App-of-Apps, Application manifest, AppProject, namespace and naming rules. This skill owns the
construction, audit and migration workflow and does not restate those rules.

| Reference | Holds |
| --- | --- |
| [Repository design](references/repository-design.md) | Multi-cluster model, wave table, project and namespace reasoning, new-repository detail |
| [PVC-safe migration](references/pvc-safe-migration.md) | Inventory, ownership handoffs, wrapper consolidation, AppProject rollout, namespace data moves |
| [Audit and validation](references/audit-and-validation.md) | Audit report and priorities, guardrails, phase checks, troubleshooting |
| [Single-cluster example](./examples/single-cluster.md) | Discovery tree, seed projects, leaf Applications and ownership map |

## Prerequisites

- Read-only access to the Git repository and cluster
- `git`, `kubectl`, and `yq`
- A current backup or snapshot mechanism for every stateful workload in migration scope
- Explicit approval before committing, pushing, or changing live Argo CD resources
- The target cluster and repository ownership model, including whether one repository manages one
  cluster or several clusters

## Modes

| Mode | Contract |
| --- | --- |
| `create` | Build a new repository through the New Repository Workflow |
| `audit` | Make no edits; report findings by priority with ordered corrections |
| `align` | Apply the smallest ordered corrections an audit recommends |
| `plan` | Produce the phased migration plan and inventory without editing |
| `migrate` | Execute the Required Migration Workflow one phase at a time |

Read [the PVC-safe migration reference](references/pvc-safe-migration.md) before changing any
Application, ApplicationSet, Helm release name, namespace, StatefulSet, or PVC.

## Structural Invariants

Keep these true for greenfield repositories and after every later change:

- every recursively discovered document is an `Application` or `ApplicationSet`;
- the seeded root is outside the tree it recursively discovers;
- raw manifests, Helm values, charts, patches, generated output, archives, and secrets are outside
  every Applications-only tree;
- each deployable unit has one intended Argo CD owner;
- an Application source path is not also owned as raw resources by an ancestor;
- wrappers exist only when they add a real lifecycle, policy, destination, or generation boundary;
- direct child Applications carry their own dependency waves;
- destination namespace, Helm release name, and resource names are explicit where defaults could
  change identity;
- AppProjects grant the minimum source, destination, namespaced-kind, and cluster-kind permissions;
- namespace placement follows ownership and trust rather than a broad technology or environment
  category;
- every stateful workload has a documented and proven restore route.

## New Repository Workflow

Each step is detailed in
[New Repository Details](references/repository-design.md#new-repository-details).

1. **Define boundaries**: classify every component and record its trust, destination, state and
   lifecycle. One repository may manage several clusters only with one root per cluster
   ([models](references/repository-design.md#repository-models)).
2. **Seed bootstrap and projects**: create the root outside its discovery tree with a pre-existing,
   constrained project; reconcile other AppProjects in the earliest wave.
3. **Add leaf Applications**: one leaf per deployable unit, with
   [dependency waves](references/repository-design.md#dependency-ordering) on direct children and
   stable Helm release names.
4. **Add runtime isolation**: pair ownership-based namespaces with RBAC, policies, quotas and secrets
   ([namespaces](references/repository-design.md#namespace-boundaries)).
5. **Prove bootstrap**: render, then bootstrap a disposable cluster from only the seeded root when
   practical.

## Required Migration Workflow

1. **Inventory before editing**: record Applications, finalizers, tracking IDs, waves, wrapper-owned
   resources and full PVC identity
   ([preflight inventory](references/pvc-safe-migration.md#preflight-inventory)).
2. **Build the Applications-only tree** without changing the active root, source paths, namespaces,
   release names or resource names
   ([tree](references/pvc-safe-migration.md#building-the-applications-only-tree)).
3. **Remove wrapper ownership safely**: finalizer off and verified before the root switch; restore
   finalizers after adoption
   ([consolidation](references/pvc-safe-migration.md#root-and-wrapper-consolidation),
   [handoff](references/pvc-safe-migration.md#application-ownership-handoff)).
4. **Verify resource identity**: PVC UID/PV, release name, namespace and resource names must not
   change ([invariants](references/pvc-safe-migration.md#invariants)).
5. **Introduce AppProjects separately**, never combined with a handoff or namespace move
   ([AppProjects](references/pvc-safe-migration.md#introducing-appprojects)).
6. **Migrate namespaces separately** as planned data migrations, stateless first and stateful last,
   one workload at a time ([namespace migration](references/pvc-safe-migration.md#namespace-migration)).

Validate after every phase with the
[phase checks](references/audit-and-validation.md#phase-validation) and stop on any
[stop condition](references/pvc-safe-migration.md#stop-conditions).

## Conformance Audit

- Use `scope=audit` before adding a major workload, after changing bootstrap discovery, and
  periodically for every managed cluster.
- Report the [audit items and priorities](references/audit-and-validation.md#conformance-audit) and
  recommend the smallest ordered corrections. Never report directory tidiness alone as a security
  improvement.
- Add the [automation guardrails](references/audit-and-validation.md#automation-guardrails); keep
  live ownership, CRD readiness, project enforcement and restore correctness as runtime gates.

## Maintaining This Skill

- Argo CD Application, AppProject and sync-option fields as Argo CD releases change them.
- Structural invariants and migration steps proven or corrected during a repository migration.
- Keep example discovery paths, source ownership, project grants and bootstrap prerequisites aligned;
  static fixture checks do not prove Application health ordering or live authorization.
