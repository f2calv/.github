---
name: nginx-ingress-migration
description: 'Migrate Kubernetes community ingress-nginx to F5 NGINX Ingress Controller OSS with parallel-by-default rollout, explicit compatibility mapping, staged cutover and rollback. Use for ingress-nginx controller, Ingress, TCP/UDP or authentication migrations.'
argument-hint: '[repository=path] [scope={audit|plan|migrate|cleanup}]'
user-invocable: true
compatibility: 'Planning is cross-platform. Rendering requires Helm; live verification requires kubectl and cluster access.'
---

# NGINX Ingress Migration

## Overview

Migrate from the Kubernetes community `ingress-nginx` controller to F5 NGINX Ingress Controller
OSS without treating the controllers as interchangeable. Preserve application behavior, introduce
the new controller beside the old one, move one route at a time, and retain an independently
deployable rollback path until production evidence supports cleanup.

Prefer the smallest safe diff. Do not redesign application routing, rename Services, rotate
credentials, change TLS ownership, or replace the active LoadBalancer address in the same step
unless the migration requires it.

## Prerequisites

- Read repository instructions, Helm values, Argo CD Applications, overlays, and operational
  documentation before editing.
- Resolve the exact source and target controller/chart versions. Read their pinned chart values,
  schemas, CRDs, and release notes rather than assuming current defaults.
- Inventory live state only with explicit approval and read-only access.
- Obtain approval before running tests, Helm suites, cluster commands, Argo operations, or any
  installation, upgrade, synchronization, DNS, certificate, or LoadBalancer mutation.
- Never copy live credentials, private endpoints, fixed addresses, or environment identifiers into
  examples, fixtures, output, or logs.

## Quick Start

1. Inventory controller ownership, routes, annotations, TLS, authentication, and L4 exposure.
2. Build a route-by-route compatibility ledger using
   [the migration reference](references/compatibility-and-rollout.md).
3. Add F5 NGINX Ingress Controller OSS in a dedicated namespace with a distinct `IngressClass`.
4. Render and validate the new controller and migrated resources without changing active traffic.
5. Expose a separate test address and migrate low-risk routes first.
6. Cut over in stages with explicit health gates and a tested rollback action.
7. Remove ingress-nginx only after every dependency and fallback window has been cleared.

## Modes

| Mode | Contract |
| --- | --- |
| `audit` | Make no edits; report inventory, compatibility gaps, unknowns, and validation limits |
| `plan` | Produce a phased route ledger, cutover gates, rollback actions, and cleanup criteria |
| `migrate` | Apply the selected strategy and convert only approved resources in bounded stages |
| `cleanup` | Remove proven-unused ingress-nginx resources after the rollback window |

## Migration Strategy Decision

Default to parallel controllers with distinct temporary LoadBalancer addresses for
production-critical systems. This is the only strategy that permits target validation while the
source controller still serves production traffic.

A non-parallel cutover is permitted only for an explicitly identified low-criticality or homelab
environment where obtaining multiple LoadBalancer addresses for testing is impractical. Before
editing, record:

- why the environment is low criticality and why a temporary address is unavailable or
  disproportionate;
- the expected outage window, maintenance notification, stop conditions, and operator;
- the immutable source, target, and cutover Git commits and pull requests;
- the exact rollback procedure: revert the cutover commit or synchronize the last known-good
  immutable revision, then verify source-controller health;
- what can be validated offline and what remains unproven until the outage.

Never perform a non-parallel cutover through uncommitted manifests or ad hoc live edits. Keep the
source configuration and controller version reproducible from Git, and do not delete them during
the rollback window. Describe the operation as an outage-bearing replacement; never claim or imply
zero downtime.

## Required Workflow

### 1. Discover the Current Contract

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

### 2. Build a Compatibility Ledger

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

For each host used by multiple Ingress resources, choose one supported target model before
migration: one mergeable master plus minions, one consolidated Ingress, or a VirtualServer with
VirtualServerRoutes. Do not point several ordinary F5 Ingress resources at the same host and wait
for one to win. Treat `All hosts are taken by other resources` as a design failure, not rollout
propagation.

### 3. Design Independent Parallel Ownership

- Install F5 NGINX Ingress Controller OSS in a dedicated namespace. Do not reuse the ingress-nginx
  namespace, release name, Service, ServiceAccount, admission resources, or ConfigMap.
- Create a distinct, non-default `IngressClass` with the target controller value required by the
  pinned F5 chart. Keep ingress-nginx's class and default status unchanged during migration.
- Configure both controllers to watch only their intended class. Do not enable classless Ingress
  handling or make the new class default while classless resources remain.
- Pin the OSS chart/image and enable only OSS-supported features. Do not introduce NGINX Plus
  resources or settings.
- Install the target CRDs and any `GlobalConfiguration` before resources that depend on them.
  Establish Argo CD sync waves or separate Applications where ordering is required.
- Account for CRD and namespace lifecycle explicitly. Helm does not remove installed CRDs during
  ordinary uninstall or Argo pruning, and a namespace can survive after its Application is gone.
  Define declarative cleanup and verify it during rollback exercises.
- Preserve controller availability, security context, scheduling, observability, and network access
  unless a documented incompatibility requires a narrow change.

### 4. Handle LoadBalancer Addresses Safely

Under the default parallel strategy, give the target controller a distinct temporary LoadBalancer
address. For a fixed address:

1. Identify whether allocation is controlled by a Service field, provider annotation, address-pool
   annotation, or external reservation.
2. Preserve the provider-specific mechanism and verify the address is reserved, unassigned, in the
   correct scope, and permitted by policy.
3. Keep the active address attached to ingress-nginx during parallel validation. Never request the
   same exclusive address for both Services.
4. Record Service status, DNS TTL, certificate routing, source ranges, firewall rules, health checks,
   and `externalTrafficPolicy` before cutover.
5. Use a temporary hostname, direct address, or controlled client override for testing.

Prefer a reversible DNS or provider-supported address reassignment at cutover. If the final address
must move between Services, define the exact detach/attach order, expected outage, ownership checks,
timeouts, and rollback before starting.

Under an approved non-parallel strategy, do not create a second address. Validate rendered
resources offline, schedule the documented outage, detach or remove the source controller's claim,
and only then let the target claim the address. Roll back through the recorded immutable Git
revision if any ownership, health, or behavior gate fails.

### 5. Convert HTTP and L4 Resources

Use [the migration reference](references/compatibility-and-rollout.md) for annotation and resource
mapping rules.

- Clone an Ingress into a temporary, distinctly named resource only when parallel host validation
  requires it; otherwise change `spec.ingressClassName` in one controlled Git step.
- Preserve hosts, paths, `pathType`, backend Services/ports, TLS Secrets, and cert-manager ownership.
- Replace each source annotation only after its F5 OSS behavior and value syntax are verified.
- Convert ingress-nginx TCP/UDP ConfigMap entries into explicitly allowed `GlobalConfiguration`
  listeners and one or more matching `TransportServer` resources. Expose the same ports on the
  target controller Service and Pod.
- Keep listener names unique and protocol-specific. Verify that every `TransportServer` listener
  name and protocol matches its `GlobalConfiguration` entry.
- Query the target Service and EndpointSlices before preserving an L4 mapping. A stale ConfigMap can
  name a Service that no longer exists or an optional backend that was retired; record such source
  defects separately from migration regressions.
- For Basic Auth, create a migration Secret whose F5-required data key is `htpasswd`; do not mutate
  the source Secret's `auth` key while ingress-nginx still consumes it. Point the migrated Ingress
  at the new Secret through the F5 Basic Auth annotation.
- For an approved non-parallel cutover, a coordinated key rename can be acceptable when source and
  target never consume the Secret concurrently. Render all owners together and retain the exact Git
  reversal; do not leave one controller reading `auth` while the other expects `htpasswd`.
- Decode or print neither htpasswd data nor TLS/private key material. Verify key presence and Secret
  references only.

### 6. Validate Before Traffic

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

Ask before running tests or suites. Ask separately before accessing a cluster. When authorized,
verify controller logs/events, configuration acceptance, status, readiness, metrics, certificates,
client source IP, HTTP behavior, WebSockets/gRPC, and TCP/UDP flows from representative clients.

Do not treat an Ingress status address as acceptance evidence: status can remain populated after a
resource is rejected. Require a current controller `AddedOrUpdated` event or equivalent accepted
state, no new rejection in an observation window, and a protocol-aware request to the intended
backend. Historical Kubernetes events remain visible after repair; separate them by timestamp from
current logs and events.

### 7. Roll Out and Cut Over in Stages

For the default parallel strategy:

1. Deploy the target controller and CRDs with no production Ingress ownership.
2. Validate the separate LoadBalancer address and controller health.
3. Migrate one low-risk route, then routes grouped by shared behavior.
4. Pause after each stage for error-rate, latency, status-code, certificate, connection, and
   controller-reload evidence.
5. Migrate TCP/UDP listeners individually; verify protocol-level behavior before continuing.
6. Lower DNS TTL ahead of DNS cutover when policy permits, then wait out the previous TTL.
7. Move the final address or DNS only after all gates pass. Keep ingress-nginx deployable and its
   manifests intact throughout the rollback window.

For an approved non-parallel strategy, perform all possible static and rendered validation first,
then execute the source stop, address release, target deployment, and verification inside the
planned outage. Treat the first failed gate or expired timebox as an immediate Git-backed rollback.
Report the actual outage and never characterize the result as zero downtime.

Every stage must have a named owner, success threshold, observation interval, stop condition, and
one-step traffic rollback. Roll back before debugging if a production stop condition is met.

### 8. Establish Monitoring and GitOps Convergence

- Enable the F5 chart metrics endpoint and its metrics Service.
- Create a ServiceMonitor or PodMonitor whose labels and namespace match the Prometheus instance's
  actual selectors. Pod scrape annotations are not evidence when the Prometheus deployment uses
  operator-managed monitor discovery.
- Query Prometheus target discovery and require one active healthy target with no scrape error.
  Then verify dashboards and alerts use the target's actual metric names.
- Compare the rendered LoadBalancer Service with the live Service. First declare stable behavior
  through chart values, such as NodePort allocation and IP family policy.
- Treat ClusterIP(s), health-check NodePort, individual NodePorts, and provider allocation-status
  annotations as runtime assignments unless the platform deliberately fixes them.
- If Argo CD still reports drift, add the narrowest `ignoreDifferences` entry scoped by group, kind,
  namespace, and exact Service name. Ignore only proven runtime-assigned JSON pointers or JQ paths,
  enable `RespectIgnoreDifferences=true`, and verify the Application becomes Synced/Healthy.
- Never ignore the entire Service spec, annotations map, LoadBalancer address request, ports,
  selectors, traffic policy, or user-owned provider annotations.

### 9. Clean Up Only After Proof

Before removing ingress-nginx, prove that:

- no Ingress, legacy class annotation, TCP/UDP entry, DNS record, LoadBalancer, firewall rule,
  monitor, policy, or runbook depends on it;
- the new class owns every intended route and all migrated resources are accepted;
- the agreed rollback window and DNS caches have expired;
- dashboards, alerts, backups, and operational ownership now target F5 NGINX Ingress Controller;
- Argo CD will not prune shared Secrets, Services, CRDs, or namespaces still in use.
- target CRDs and the target namespace are either intentionally retained or explicitly removed;
  pruning the Helm Application is not proof that either was deleted.

Remove old routes and L4 configuration first, then the old controller Application/release, and
finally controller-specific namespace and CRDs only when no remaining resource uses them. Release
obsolete addresses or reservations last. Keep the compatibility ledger and validation evidence as
durable migration documentation.

Published tags and releases from a failed attempt remain immutable evidence. Never move or delete
them after rollback; publish a later version that records the recovered state.

### 10. Reconcile the Tracking Issue

Review every issue checkbox against the final evidence. Mark completed items, and comment on items
that were intentionally not done, superseded by a different strategy, or moved to a separate
workstream. Name the replacement decision and durable follow-up rather than leaving ambiguous
unchecked boxes. Close the issue only when all migration acceptance criteria are proven or every
remaining item has an explicit non-blocking owner elsewhere.

## Stop Conditions

Stop and report rather than guess when:

- a source annotation, custom template, snippet, module, or ConfigMap behavior has no proven F5 OSS
  equivalent;
- the target and source would claim the same class, host, exclusive address, or listener;
- the final fixed address cannot be moved reversibly;
- rendered output introduces unexpected cluster-scoped resources or ownership changes;
- a TLS, authentication, source-IP, TCP/UDP, or application health check fails;
- the controller has no healthy Prometheus target when monitoring is an acceptance criterion;
- Argo CD remains OutOfSync for an unexplained or broadly ignored resource difference;
- rollback depends on deleted manifests, released addresses, expired credentials, or an
  unavailable source controller.

## Handoff

Report:

- files and controller contracts changed;
- compatibility-ledger totals by direct, converted, unsupported, and unresolved mapping;
- source and target namespaces, classes, and address strategy using safe placeholders where public;
- static, rendered, Argo, and live checks run with results;
- tests and live operations not run, with the approval still required;
- current rollout stage, remaining gates, rollback action, fallback expiry, and cleanup work.
