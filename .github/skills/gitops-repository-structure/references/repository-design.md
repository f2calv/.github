# GitOps Repository Design

Choose repository models, dependency waves, AppProject grants and namespaces for a new or aligned
App-of-Apps repository.

The Kubernetes GitOps instructions (`.github/instructions/kubernetes.gitops.instructions.md`) own the baseline layout, App-of-Apps,
Application manifest, AppProject, namespace and naming rules. This reference adds only the design
reasoning the skill applies on top of them.

## Repository Models

Use the [single-cluster worked example](../examples/single-cluster.md) for a concrete discovery
tree, seed projects, direct leaf Applications and an ownership/permission map. Its bootstrap
prerequisites and live migration gates are explicit; the steady-state manifests are not a handoff
procedure.

For one cluster, use one seeded root Application with the default layout from the instructions when
access and lifecycle boundaries permit it. The root source is `src/applications` with recursive
directory discovery. Leaf Applications may point to Helm repositories, OCI charts, or directories
under `resources/`. Do not recursively scan `src` itself: a mixed tree eventually applies a Secret,
values file, archived manifest, or Helm template as though it were an Argo Application.

For a repository that manages several clusters, repeat the boundary explicitly:

```text
clusters/
├── cluster-a/
│   ├── bootstrap.yaml
│   └── applications/
├── cluster-b/
│   ├── bootstrap.yaml
│   └── applications/
└── resources/
   ├── base/
   └── overlays/
      ├── cluster-a/
      └── cluster-b/
```

Each cluster root discovers only its own Applications tree and has only the destination permissions
that cluster requires. Share charts, bases, or values deliberately under `resources`; do not use a
single broadly privileged root merely to avoid small cluster-specific entry points.

Repository folders describe source ownership and reuse. They do not create Kubernetes isolation,
RBAC, network policy, secret boundaries, or data protection.

## Dependency Ordering

Put `argocd.argoproj.io/sync-wave` on direct child Applications:

| Typical wave | Responsibility |
| --- | --- |
| `-4` | Cluster networking and storage prerequisites |
| `-3` | Certificate and security controllers |
| `-2` | GitOps controller self-management |
| `0` | Shared operators and data services |
| Positive | Observability and application workloads |

Use the numbers as a repository-specific dependency graph, not a universal taxonomy. Child waves
gate a clean-cluster bootstrap only when Application health assessment is configured as the
instructions require; verify it first. A sync wave does not replace runtime readiness, CRD
availability checks, or application retry behavior.

## Authorization Boundaries

Apply the AppProject rules from the instructions, including in a single-operator repository.
AppProjects are preventive guardrails and executable ownership documentation, not merely multi-team
UI grouping.

Choose projects from real permission boundaries rather than mechanically creating one per
Application. A typical starting model separates cluster foundation, shared services, and
independently owned applications. Split a project further only when source trust, destinations,
resource kinds, secrets, operators, or lifecycle differ.

## Namespace Boundaries

Apply the namespace rules from the instructions. Environment can remain a label, configuration
dimension, or suffix where multiple instances are required. It should not be the only isolation
boundary between unrelated applications.

Namespace separation is not a security control by itself. Pair new application namespaces with
least-privilege service accounts and RBAC, default-deny NetworkPolicies plus tested DNS and service
exceptions, intentional secret distribution, and resource limits where appropriate.

## New Repository Details

- **Define boundaries**: classify each component as cluster foundation, shared service,
  independently owned application, or environment-specific instance. Record its source trust,
  destination, cluster-scoped requirements, namespace, secrets, state, consumers, and release
  lifecycle.
- **Seed bootstrap and projects**: create the root outside its discovery tree. Pre-create or seed a
  constrained root AppProject, then reconcile other AppProjects through an earliest-wave leaf before
  dependent Applications.
- **Add leaf Applications**: give each deployable unit one leaf Application pointing to an external
  chart, OCI artifact, or a resource directory. Put dependency waves on these direct children and
  preserve stable Helm release names.
- **Add runtime isolation**: create ownership-based namespaces and their RBAC, policies, quotas,
  secrets, and monitoring access. Keep shared services shared only when their consumers,
  permissions, and lifecycle justify it.
- **Prove bootstrap**: validate render output and, in a disposable cluster when practical, bootstrap
  from only the seeded root. Confirm ordering, CRD readiness, Application health assessment,
  project permissions, namespace policies, pruning behavior, and state restoration.
