# Discovery, Validation and Cleanup Reference

Inventory the source contract, build the compatibility ledger, prove the target before traffic and
prove the source is unused before cleanup.

## Discovery Inventory

Inspect source, rendered, and—when authorized—live resources. Record:

- ingress-nginx chart/release/version, namespace, controller image, arguments, ConfigMap, admission
  webhook, default backend, metrics, Pod scheduling, PodDisruptionBudget, and NetworkPolicies;
- `IngressClass` names, `spec.controller` values, defaults, classless Ingresses, legacy
  `kubernetes.io/ingress.class`, and each `spec.ingressClassName`;
- every Ingress host, path, `pathType`, backend Service/port, TLS Secret, cert-manager annotation,
  source annotation, finalizer, and Argo CD owner;
- every host claimed by more than one Ingress, including cross-namespace claims; standard F5
  Ingress resources do not merge these implicitly, so identify the required master/minion or
  VirtualServer/VirtualServerRoute ownership before cutover;
- controller ConfigMap settings, custom templates, snippets, ModSecurity, Lua/plugins, forwarded
  headers, proxy protocol, real-IP trust, and global defaults;
- Service type, ports, node ports, `externalTrafficPolicy`, health-check settings, provider
  annotations, address allocation mechanism, published status address, and DNS dependencies;
- default certificates, cross-namespace Secret references, Basic Auth Secrets, external
  authentication, allowlists, redirects, rewrites, regex paths, rate limits, affinity, canaries,
  gRPC/WebSocket behavior, buffering, body limits, and timeout settings;
- ingress-nginx TCP/UDP ConfigMaps and every exposed port, protocol, namespace/Service, target port,
  PROXY setting, and client;
- Helm, Kustomize, Argo CD, policy, schema, generated documentation, monitoring, alerting, and
  runbook surfaces that own or observe the controller.

Do not infer behavior from resource names. Compare configured defaults with both controllers'
versioned defaults and mark anything not proven as unknown. Render umbrella and aliased dependency
charts and record actual backend Service names; controller annotations must reference rendered
names, not dependency aliases or guessed release prefixes.

## Compatibility Ledger

Create one row per route or L4 listener:

| Source | Source behavior | F5 OSS target | Evidence | Validation | Cutover | Rollback |
| --- | --- | --- | --- | --- | --- | --- |
| Ingress or listener | Exact annotation/config | Annotation, resource, policy, or unsupported | Docs/render/live | Request or protocol check | Traffic switch | Exact reversal |

Classify every source feature as:

- direct Kubernetes field with unchanged semantics;
- F5 `nginx.org/*` annotation with verified version-specific syntax;
- F5 custom resource or Policy;
- controller-wide Helm/ConfigMap setting;
- requires an application, proxy, DNS, or certificate change;
- unsupported or intentionally removed.

Never bulk-replace annotation prefixes. Annotation names, value syntax, scope, defaults, and merge
behavior differ. Resolve every row before moving its traffic; unsupported critical behavior blocks
cutover.

## Static Validation

Use repository-pinned tools and wrappers. Static validation should cover:

1. YAML, Markdown, schema, and policy diagnostics;
2. Helm dependency/lock consistency and `helm lint`;
3. `helm template` for source and target values with CRDs available to validation;
4. normalized rendered-resource comparison, accounting for every intentional difference;
5. Argo CD rendering/diff without sync, prune, or live mutation;
6. distinct namespaces, release names, classes, selectors, webhook names, Services, addresses, and
   status publication;
7. all compatibility-ledger rows, including expected rejection of invalid or unsupported settings.

For Helm-generated routes, assert that protocol annotations equal actual rendered Service names,
every shared host has exactly one master or consolidated owner, masters contain no paths, minions
contain no TLS or conflicting paths, and every Ingress or TransportServer receives an accepted or
valid controller event.

## Live Acceptance Evidence

Ask before running tests or suites. Ask separately before accessing a cluster. When authorized,
verify controller logs/events, configuration acceptance, status, readiness, metrics, certificates,
client source IP, HTTP behavior, WebSockets/gRPC, and TCP/UDP flows from representative clients.

Do not treat an Ingress status address as acceptance evidence: status can remain populated after a
resource is rejected. Require a current controller `AddedOrUpdated` event or equivalent accepted
state, no new rejection in an observation window, and a protocol-aware request to the intended
backend. Historical Kubernetes events remain visible after repair; separate them by timestamp from
current logs and events.

A 401 response without credentials does not prove a Basic Auth file exists: NGINX emits the
challenge before it attempts password verification. Use the materialization checks in
[Basic Auth Secrets](compatibility-and-rollout.md#basic-auth-secrets).

## Cleanup Proof

Before removing ingress-nginx, prove that:

- no Ingress, legacy class annotation, TCP/UDP entry, DNS record, LoadBalancer, firewall rule,
  monitor, policy, or runbook depends on it;
- the new class owns every intended route and all migrated resources are accepted;
- the agreed rollback window and DNS caches have expired;
- dashboards, alerts, backups, and operational ownership now target F5 NGINX Ingress Controller;
- Argo CD will not prune shared Secrets, Services, CRDs, or namespaces still in use;
- target CRDs and the target namespace are either intentionally retained or explicitly removed;
  pruning the Helm Application is not proof that either was deleted.

Remove old routes and L4 configuration first, then the old controller Application/release, and
finally controller-specific namespace and CRDs only when no remaining resource uses them. Release
obsolete addresses or reservations last. Keep the compatibility ledger and validation evidence as
durable migration documentation.

Published tags and releases from a failed attempt remain immutable evidence. Never move or delete
them after rollback; publish a later version that records the recovered state.
