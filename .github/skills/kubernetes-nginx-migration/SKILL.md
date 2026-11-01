---
name: kubernetes-nginx-migration
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

| Reference | Holds |
| --- | --- |
| [Discovery, validation and cleanup](references/discovery-and-validation.md) | Inventory checklist, ledger format, validation evidence, cleanup proof |
| [Compatibility and rollout](references/compatibility-and-rollout.md) | Strategy record, annotation/resource mapping, Secrets, L4, addresses, monitoring, gates |
| [Parallel route example](./examples/parallel-route.md) | Old/new Ingress pair, class identities, difference ledger, rollback gates |

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
environment where multiple LoadBalancer addresses are impractical. Write its decision record and
commit every state to Git before editing, as defined in
[Migration Strategy](references/compatibility-and-rollout.md#migration-strategy); never claim zero
downtime.

## Required Workflow

### 1. Discover the Current Contract

- Inventory controller, classes, routes, TLS, authentication, shared hosts, L4 listeners and owning
  tooling using the [discovery inventory](references/discovery-and-validation.md#discovery-inventory).
- Do not infer behavior from resource names; mark anything not proven as unknown.
- Record rendered backend Service names, not dependency aliases or guessed release prefixes.

### 2. Build a Compatibility Ledger

- Create one classified row per route or L4 listener using the
  [ledger format](references/discovery-and-validation.md#compatibility-ledger) and the
  [annotation decisions](references/compatibility-and-rollout.md#http-annotation-decisions).
- Never bulk-replace annotation prefixes. Unsupported critical behavior blocks cutover.
- Give each shared host one supported owner model before migration, per
  [Shared Hosts](references/compatibility-and-rollout.md#shared-hosts-and-mergeable-ingress).

### 3. Design Independent Parallel Ownership

- Install the target in a dedicated namespace with a distinct, non-default `IngressClass`; each
  controller watches only its own class. Use OSS features only.
- Install CRDs and `GlobalConfiguration` before dependents and plan CRD/namespace cleanup; see
  [Parallel Controller Ownership](references/compatibility-and-rollout.md#parallel-controller-ownership).

### 4. Handle LoadBalancer Addresses Safely

- Parallel: give the target a distinct temporary address; never request the same exclusive address
  for both Services.
- Non-parallel: create no second address; release the source claim before the target claims it,
  inside the outage. Follow the
  [address decision](references/compatibility-and-rollout.md#fixed-loadbalancer-address-decision).

### 5. Convert HTTP and L4 Resources

- Preserve hosts, paths, backends, TLS and cert-manager ownership; replace an annotation only after
  its F5 OSS behavior is verified ([conversion](references/compatibility-and-rollout.md#converting-ingress-resources)).
- Make every ACME HTTP-01 certificate solve in place
  ([ACME](references/compatibility-and-rollout.md#acme-http-01-certificates)).
- Basic Auth needs a `nginx.org/htpasswd` Secret with key `htpasswd`; follow
  [Basic Auth Secrets](references/compatibility-and-rollout.md#basic-auth-secrets) for parallel
  Secrets and one-time forced type replacement.
- Convert TCP/UDP entries to `GlobalConfiguration` listeners and `TransportServer`s per
  [TCP and UDP](references/compatibility-and-rollout.md#tcp-and-udp).

### 6. Validate Before Traffic

- Run the [static validation](references/discovery-and-validation.md#static-validation) with
  repository-pinned tools; ask before tests and separately before cluster access.
- An Ingress status address or an unauthenticated 401 is not acceptance evidence; require the
  [live acceptance evidence](references/discovery-and-validation.md#live-acceptance-evidence).
- Pass the [Helm and Argo CD gates](references/compatibility-and-rollout.md#helm-and-argo-cd-gates)
  without syncing.

### 7. Roll Out and Cut Over in Stages

- Follow [Staged Cutover](references/compatibility-and-rollout.md#staged-cutover); keep
  ingress-nginx deployable and its manifests intact throughout the rollback window.
- Give every stage the owner, thresholds and one-step rollback in
  [Cutover and Rollback Gates](references/compatibility-and-rollout.md#cutover-and-rollback-gates).
  Roll back before debugging if a production stop condition is met.

### 8. Establish Monitoring and GitOps Convergence

- Require one active, healthy Prometheus target, per
  [Prometheus Discovery](references/compatibility-and-rollout.md#prometheus-discovery).
- Ignore only proven runtime-assigned Service fields, per
  [Argo CD Service Drift](references/compatibility-and-rollout.md#argo-cd-service-drift).

### 9. Clean Up Only After Proof

- Satisfy the [cleanup proof](references/discovery-and-validation.md#cleanup-proof); remove routes
  and L4 configuration, then the controller, then namespace and CRDs, and release addresses last.
- Never move or delete published tags from a failed attempt.

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

## Maintaining This Skill

- Annotation and ConfigMap compatibility mappings in the compatibility reference as either
  controller releases new versions.
- Rollout stages, gates and rollback actions proven during a cutover.
- Keep the route pair, expected class identities and exact-diff assertions aligned with the
  selected controller contracts; never promote offline fixture success into live cutover evidence.
