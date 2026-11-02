# Compatibility and Rollout Reference

Map ingress-nginx behavior to F5 NGINX Ingress Controller OSS and stage the cutover and rollback.

Use this reference after inventorying the exact community ingress-nginx and F5 NGINX Ingress
Controller OSS versions. It is a decision guide, not a mechanical translation table. Confirm every
target field against the pinned F5 chart, CRDs, and documentation before editing.

## Controller Identity

The two controllers are independent implementations.

| Concern | Community ingress-nginx | F5 NGINX Ingress Controller OSS migration rule |
| --- | --- | --- |
| Annotation prefix | `nginx.ingress.kubernetes.io/*` | Map behavior explicitly to `nginx.org/*`, a custom resource, Policy, or controller setting |
| Ingress selection | Class name and ingress-nginx controller value | Use a new class name and the F5 controller value emitted or required by the pinned chart |
| Namespace | Existing ingress-nginx namespace | Use a dedicated target namespace |
| Release and Service | Existing ingress-nginx identity | Use distinct names throughout parallel rollout |
| Default class | May be default | Keep the F5 class non-default until all classless Ingresses are resolved |

Do not configure both controllers with the same class name or `spec.controller` claim. Inspect the
rendered `IngressClass`; chart value names and defaults can change between releases.

## Migration Strategy

Use parallel controllers with distinct temporary LoadBalancer addresses by default, and always for
production-critical systems. Parallel operation proves the target independently and keeps traffic
rollback separate from controller reconstruction.

Permit a non-parallel cutover only for a documented low-criticality or homelab environment where
multiple LoadBalancer addresses are impractical. Before editing, record:

- why the environment is low criticality and why a temporary address is unavailable or
  disproportionate;
- the expected outage window, maintenance notification, timebox, stop conditions, and operator;
- the immutable source, target, and cutover Git commits and pull requests;
- the exact rollback procedure: revert the cutover commit or synchronize the last known-good
  immutable revision, then verify source-controller health;
- what can be validated offline and what remains unproven until the outage.

Source, target, and cutover states must exist as immutable Git commits reviewed through pull
requests before the outage. Never perform a non-parallel cutover through uncommitted manifests or
ad hoc live edits. Rollback means reverting the cutover commit or synchronizing the recorded last
known-good revision, not rebuilding source manifests from memory or live state.

Describe the operation as an outage-bearing replacement; never claim or imply zero downtime.
Preserve the source controller manifests, version, credentials references, and address settings in
Git, and do not delete them, until the target passes its observation window.

## Parallel Controller Ownership

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

## HTTP Annotation Decisions

Common concepts have different syntax or no exact equivalent. The target column names candidate
F5 OSS features to verify; it does not guarantee equivalence.

| ingress-nginx behavior | Candidate F5 OSS mechanism | Required checks |
| --- | --- | --- |
| `proxy-body-size` | `nginx.org/client-max-body-size` | Units, zero/unlimited behavior, and inherited default |
| `proxy-read-timeout` | `nginx.org/proxy-read-timeout` | Value format and streaming behavior |
| `proxy-send-timeout` | `nginx.org/proxy-send-timeout` | Value format and upstream behavior |
| `proxy-connect-timeout` | `nginx.org/proxy-connect-timeout` | Value format and target default |
| `ssl-redirect` or `force-ssl-redirect` | `nginx.org/redirect-to-https` or controller setting | Forwarded-proto handling, ports, and redirect status |
| `rewrite-target` | `nginx.org/rewrites` or VirtualServer route action | Service-specific syntax, captures, query strings, and path preservation |
| `use-regex` | F5 path/route syntax | Regex dialect, case sensitivity, precedence, and path validation |
| `backend-protocol` | Protocol-specific F5 annotation/resource | HTTP/HTTPS/gRPC behavior and upstream TLS verification |
| `auth-type`, `auth-secret`, `auth-realm` | `nginx.org/basic-auth-secret` | Secret key must be `htpasswd`; realm and failure behavior may differ |
| `whitelist-source-range` | F5 allow/deny mechanism or Policy | CIDR parsing, forwarded client IP, and trusted proxies |
| rate-limit annotations | F5 rate-limit annotation or Policy | Key, zone sharing, burst, rejection code, and replica behavior |
| affinity/session-cookie annotations | F5 sticky-cookie support | OSS availability, cookie attributes, and failover behavior |
| canary annotations | Separate resource or external traffic split | F5 OSS has no assumed annotation-for-annotation canary equivalent |
| auth URL/sign-in annotations | External auth capability or application proxy | Headers, redirects, caching, TLS, and OSS support |
| configuration/server/location snippets | F5 snippets, template, or redesign | Security policy, enablement, context, ordering, and unsupported directives |

Also compare controller ConfigMap defaults. An absent per-Ingress annotation does not mean behavior
is unchanged when timeout, buffering, redirect, header, TLS, or real-IP defaults differ.

Replace each source annotation only after its F5 OSS behavior and value syntax are verified.

## Converting Ingress Resources

- Clone an Ingress into a temporary, distinctly named resource only when parallel host validation
  requires it; otherwise change `spec.ingressClassName` in one controlled Git step.
- Preserve hosts, paths, `pathType`, backend Services/ports, TLS Secrets, and cert-manager ownership.
- Decode or print neither htpasswd data nor TLS/private key material. Verify key presence and Secret
  references only.

## Shared Hosts and Mergeable Ingress

F5 NGINX Ingress Controller does not implicitly merge several ordinary Ingress resources claiming
one host. Group Ingresses by host before cutover and convert each duplicate-host group to a
supported ownership model: one mergeable master plus minions, one consolidated Ingress, or a
VirtualServer with VirtualServerRoutes. Do not point several ordinary F5 Ingress resources at the
same host and wait for one to win.

For mergeable Ingress, exactly one master owns one host, TLS, certificate issuance, redirects, and
host-wide policy but no paths. Minions carry the same host, non-conflicting paths, no TLS, and
route-specific authentication, rewrite, timeout, or protocol annotations where supported. Masters
and minions may cross namespaces, while Secrets and backend Services remain namespace-local under
their normal resource semantics.

Reject a plan with zero or multiple masters, paths on a master, TLS on a minion, or conflicting
minion paths. `All hosts are taken by other resources` proves conversion was incomplete; treat it as
a design failure, not rollout propagation.

Annotations that identify Services must use rendered Kubernetes Service names. Umbrella aliases
are not Service names because Helm commonly prefixes them with the release. Prefer a reusable chart
contract that derives annotation values from the same fullname helper used by the Service and
Ingress backend, then assert the exact rendered value.

## ACME HTTP-01 Certificates

Make every ACME HTTP-01 certificate on an F5-served host solve in place. F5 NGINX gives a host to
its oldest resource, so cert-manager's separate solver Ingress is rejected and renewals fail
silently until expiry:

- Annotate a regular Ingress with `acme.cert-manager.io/http01-edit-in-place: "true"`.
- A mergeable master has no paths. Declare its `Certificate` explicitly with
  `acme.cert-manager.io/http01-override-ingress-name` set to an always-present minion, and remove
  the master's issuer annotation.
- Under Argo CD self-heal, add a global `resource.customizations.ignoreDifferences` rule for
  Ingress paths whose backend starts with `cm-acme-http-solver-`, or self-heal removes the
  transient path before validation.
- Remove chart-generated `Certificate`s that write the same Secret as an ingress-shim one.
- After cutover, confirm that every public certificate renews; do not rely on `Ready=True`, which
  stays true until expiry.

## Basic Auth Secrets

Community ingress-nginx commonly reads an htpasswd file from the Secret data key `auth`. F5 NGINX
Ingress Controller 5.6.3 expects the referenced Secret to have type `nginx.org/htpasswd` and contain
the file in data key `htpasswd`.

During parallel operation:

1. Keep the source Secret unchanged; do not mutate its `auth` key while ingress-nginx still
   consumes it.
2. Create a separately named target Secret with type `nginx.org/htpasswd` and the same htpasswd
   bytes under `htpasswd`, using a secret-safe process outside public examples.
3. Reference it with the version-supported F5 Basic Auth annotation.
4. Verify a valid credential, an invalid credential, no credential, response code, challenge
   header, and realm.
5. Delete the source Secret only after no ingress-nginx Ingress references it and rollback has
   expired.

For an approved non-parallel cutover, a coordinated key rename can be acceptable when source and
target never consume the Secret concurrently. Render all owners together and retain the exact Git
reversal; do not leave one controller reading `auth` while the other expects `htpasswd`.

Never print or decode either Secret during inspection or validation.

An `Opaque` Secret can produce a generated `auth_basic_user_file` directive while F5 does not
materialize the referenced file under `/etc/nginx/secrets`. The unauthenticated request still
returns 401 because NGINX sends the challenge before reading the file; credential submission then
fails regardless of correctness. For every Basic Auth route, inspect the generated NGINX
configuration (`nginx -T`) for its `auth_basic_user_file`, verify that file exists inside the
controller Pod, and compare its fingerprint with the live Secret without printing content. After
materialization, verify an invalid credential returns a normal 401 and an authorized operator
confirms a valid credential succeeds.

Kubernetes makes `Secret.type` immutable. For an in-place conversion of an existing `Opaque` Secret
managed by Argo CD:

1. commit the new type and add the one-time resource annotation
   `argocd.argoproj.io/sync-options: Force=true,Replace=true`;
2. let Argo delete and recreate the Secret;
3. verify all owning Applications reconciled, the live type is correct, and the controller
   materialized the referenced auth files;
4. verify invalid credentials return 401 and an operator verifies the intended credential;
5. overwrite the annotation immediately in a second commit with
   `argocd.argoproj.io/sync-options: Force=false,Replace=false` and verify the live value changed.

Never leave forced replacement enabled for credentials: it recreates the Secret on later syncs and
can cause unnecessary authentication churn. Merely omitting the annotation might leave the live
force value behind after server-side apply or recreation changed field ownership. Remove the
explicit false annotation later only when the reconciler demonstrably deletes the live field.

## TCP and UDP

Community ingress-nginx commonly routes L4 services through controller arguments that name
TCP/UDP ConfigMaps. F5 NGINX Ingress Controller uses:

- one controller-selected `GlobalConfiguration` containing permitted listeners; and
- a `TransportServer` that references a listener and passes traffic to an upstream Service.

Convert each ingress-nginx TCP/UDP ConfigMap entry into an explicitly allowed `GlobalConfiguration`
listener and one or more matching `TransportServer` resources. Expose the same ports on the target
controller Service and Pod. Keep listener names unique and protocol-specific, and verify that every
`TransportServer` listener name and protocol matches its `GlobalConfiguration` entry.

For every source entry, preserve:

- external port and protocol;
- backend namespace, Service, and port;
- PROXY protocol expectations;
- client source-IP and idle-timeout behavior;
- target controller Service port and container listener exposure;
- firewall, network policy, health-check, and monitoring behavior.

Query the target Service and EndpointSlices before creating listeners. Do not preserve a stale
mapping merely because it exists in the source ConfigMap. A missing Service, an optional backend
that is no longer deployed, or a Service without endpoints is a source defect to resolve or remove;
record such source defects separately from migration regressions.

Representative structure:

```yaml
apiVersion: k8s.nginx.org/v1
kind: GlobalConfiguration
metadata:
  name: nginx-configuration
  namespace: nginx-ingress
spec:
  listeners:
    - name: example-tcp
      port: 12345
      protocol: TCP
---
apiVersion: k8s.nginx.org/v1
kind: TransportServer
metadata:
  name: example-tcp
  namespace: example
spec:
  listener:
    name: example-tcp
    protocol: TCP
  upstreams:
    - name: example
      service: example
      port: 12345
  action:
    pass: example
```

Use synthetic names and ports in reusable examples. Verify the CRD schema for the pinned version.
For UDP, use a UDP listener and matching TransportServer protocol, expose a UDP Service port, and
test with a protocol-aware client rather than a TCP connection check.

## Fixed LoadBalancer Address Decision

Determine the address authority before changing values:

| Authority | Typical representation | Migration action |
| --- | --- | --- |
| Kubernetes implementation | `spec.loadBalancerIP` where still supported | Confirm provider support and exclusivity |
| Cloud controller | Service annotation or provider resource reference | Preserve the exact provider contract |
| Bare-metal load balancer | Address-pool annotation or requested address | Reserve a distinct parallel address |
| External appliance or proxy | Out-of-cluster mapping | Coordinate mapping and health checks separately |
| DNS only | Record targeting the Service address | Use a temporary validation record and planned TTL |

Do not assume `spec.loadBalancerIP` is portable; it is deprecated by Kubernetes and ignored by some
providers. Render the target Service and verify the actual allocation mechanism.

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

Under an approved non-parallel strategy, do not create a second address. Validate everything
possible offline without claiming the address, schedule the documented outage, then detach or
remove the source controller's claim before letting the target claim the address. An inability to
release, acquire, or health-check the address within the timebox, or any failed ownership, health,
or behavior gate, triggers rollback to the recorded immutable Git revision.

## Prometheus Discovery

F5 chart metrics commonly require three separately enabled surfaces:

1. the controller metrics listener;
2. a metrics Service;
3. a ServiceMonitor or PodMonitor selected by the installed Prometheus resource.

Inspect the Prometheus `serviceMonitorSelector` and `serviceMonitorNamespaceSelector`; do not assume
the chart's default labels are selected. Apply the required selector labels and namespace through
target chart values. Pod scrape annotations are not evidence when the Prometheus deployment uses
operator-managed monitor discovery.

Query `/api/v1/targets` after reconciliation. Acceptance requires one active target with
`health=up` and no scrape error, not merely a created ServiceMonitor or Pod annotations. Then verify
dashboards and alerts use the target's actual metric names.

## Argo CD Service Drift

LoadBalancer implementations and Kubernetes allocate fields that are absent from Helm output:

- `spec.clusterIP` and `spec.clusterIPs`;
- `spec.healthCheckNodePort`;
- `spec.ports[].nodePort`;
- provider allocation-status annotations.

Treat these as runtime assignments unless the platform deliberately fixes them. Before ignoring
drift, declare stable supported behavior through chart values, including NodePort allocation and IP
family policy where applicable. Compare rendered and live resources field by field. If only runtime
allocations remain, add the narrowest `ignoreDifferences` entry scoped by group, kind, namespace,
and exact Service name, ignoring only the proven runtime-assigned JSON pointers or JQ paths. Add
`RespectIgnoreDifferences=true` and require Synced/Healthy afterward.

Never ignore the entire Service spec, the annotations map, or other broad maps or lists whose desired
content includes user-owned behavior. In particular, continue reconciling the requested
LoadBalancer address, Service ports, selectors, `externalTrafficPolicy`, source ranges, and
user-owned provider request annotations.

## Helm and Argo CD Gates

Before Argo CD sync:

1. Pin the target chart and image versions.
2. Inspect chart defaults and schema for ingress class, CRDs, custom resources,
   `GlobalConfiguration`, Service ports/address, admission, namespace, and watch scope.
3. Run repository-pinned YAML/schema checks, `helm lint`, and `helm template` with the exact values
   hierarchy Argo CD uses.
4. Include required CRDs in validation and verify their sync ordering.
5. Compare `argocd app manifests` or an offline Argo rendering/diff when authorized; do not sync.
6. Confirm the target Application cannot prune the source controller or shared application Secrets.
7. Confirm automated sync and prune cannot advance a staged route before its gate.

Separate controller installation, CRD/global configuration, route migration, traffic cutover, and
source cleanup into independently reversible Git changes or Argo Applications where practical.

## Staged Cutover

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
Report the actual outage.

## Cutover and Rollback Gates

Every stage must have a named owner, success threshold, observation interval, stop condition, and
one-step traffic rollback. Define objective thresholds for each stage:

| Gate | Example evidence | Rollback trigger |
| --- | --- | --- |
| Configuration | Resource accepted; no rejected events | Rejected or stale config |
| Availability | Ready replicas and LoadBalancer health | Readiness or health-check loss |
| HTTP | Status, headers, body, redirect, auth, TLS | Contract mismatch |
| Streaming | WebSocket/gRPC connection and duration | Upgrade, reset, or timeout failure |
| L4 | Protocol transaction and source-IP behavior | Connection or payload failure |
| Reliability | Error rate, latency, reloads, saturation | Agreed threshold exceeded |
| Ownership | Only intended class and address claimed | Dual claim or status conflict |

Rollback changes traffic first: restore the previous DNS target, address attachment, or
`ingressClassName`. Roll back before debugging if a production stop condition is met; do not
diagnose while impaired traffic remains on the target. Then verify the source controller resumed
ownership and health. Roll forward only after the defect is understood, the rendered change is
reviewed, and the same checks pass again.

## Rollback Cleanup

Rollback validation includes resources Helm and Argo CD might not remove: CRDs installed from
`crds/`, the target namespace, cluster-scoped IngressClasses, webhook resources, RBAC, and custom
resources left after Application pruning. Record which must survive for retry and which must be
removed.

Verify the source controller, class, shared-host routes, LoadBalancer address, authentication, and
protocol listeners after rollback. Historical rejection events remain visible; use current state,
new events, controller logs, and protocol probes rather than treating old events as active failure.

## Authoritative References

- [F5 NGINX Ingress Controller annotations](https://docs.nginx.com/nginx-ingress-controller/configuration/ingress-resources/advanced-configuration-with-annotations/)
- [F5 NGINX Ingress Controller GlobalConfiguration](https://docs.nginx.com/nginx-ingress-controller/configuration/global-configuration/globalconfiguration-resource/)
- [F5 NGINX Ingress Controller TransportServer](https://docs.nginx.com/nginx-ingress-controller/configuration/transportserver-resource/)
- [F5 NGINX Ingress Controller Helm parameters](https://docs.nginx.com/nginx-ingress-controller/install/helm/parameters/)
- [Kubernetes IngressClass](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class)
- [Kubernetes LoadBalancer Service](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)

Use version-specific F5 documentation and the pinned chart as the final authority.
