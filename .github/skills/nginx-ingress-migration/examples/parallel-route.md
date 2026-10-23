# Parallel Ingress Route Example

This pair demonstrates a bounded migration from community ingress-nginx to F5 NGINX Ingress
Controller OSS: body size, upstream read/send timeouts, and unchanged route/TLS references.
It does not install controllers, allocate addresses, create credentials, or prove full behavioral
equivalence. Obtain separate approval for all live validation and traffic changes.

## Inputs and Ownership

| Asset | Purpose |
| --- | --- |
| [Source Ingress](../templates/source-ingress.yaml) | Existing route remains available for rollback |
| [Target Ingress](../templates/target-ingress.yaml) | Distinct preview resource handled only by the F5 class |
| [Source class expectation](../templates/source-class.expected.yaml) | Expected source-controller identity for this non-default-class scenario |
| [Target class expectation](../templates/target-class.expected.yaml) | Expected distinct, non-default F5 identity |

The class files are **expected render contracts**, not extra resources to apply beside a Helm
release that already owns its IngressClass. Configure the selected charts to produce those
identities, then compare their rendered resources. If the existing source class is default, preserve
that status and resolve classless resources separately; do not apply this scenario's source-class
expectation to change it accidentally.

Both controllers must watch only their intended class, with separate releases, namespaces,
Services and LoadBalancer addresses. IngressClass objects alone do not configure controller watch
flags. The shared hostname is intentional across two isolated controllers, not two ordinary
Ingresses competing for the same host within F5.

The backend `example-api:8080` and TLS Secret `example-tls` already exist in namespace `example`.
The certificate is independently managed, not issued by an annotation on either example Ingress.
No Secret values or duplicate certificate owner are introduced. If the real source uses
ingress-shim/HTTP-01, follow the skill's certificate ownership and renewal procedure before using
this pair; sharing a Secret reference is not proof that renewal will work.

## Explicit Compatibility Ledger

| Concern | Source | Target | Required evidence |
| --- | --- | --- | --- |
| Resource identity | `example-route` | `example-route-f5-preview` | Distinct names permit parallel validation without changing source ownership |
| Controller selection | `ingress-nginx-example` | `nginx-f5-example` | Rendered class identities and actual controller watch configuration agree |
| Body limit | `proxy-body-size: "8m"` | `client-max-body-size: "8m"` | Same accepted/rejected body-size boundary |
| Read timeout | `"45"` seconds | `"45s"` duration | Upstream idle-read behavior matches; not a total request deadline |
| Send timeout | `"45"` seconds | `"45s"` duration | Upstream idle-write behavior matches |
| Host/path/backend | `app.example.com`, `/api`, Prefix, `example-api:8080` | Unchanged | Expected backend, path/query forwarding and trailing-slash behavior |
| TLS reference | `example-tls` in `example` | Unchanged | Correct chain/SAN, termination and independent renewal |
| Redirects, buffering, forwarded headers and other defaults | Must inventory | Must compare and configure deliberately | **Unresolved until checked; blocks traffic cutover** |

The intended file diff is limited to the resource name, ingress class and three annotation mappings.
The regression test compares every other field rather than merely checking annotation presence.
Timeout units are different; replacing the annotation prefix alone is not a valid translation.
The preserved TLS reference does not imply identical HTTP-to-HTTPS redirect codes or trust settings.

Annotation syntax is grounded in the
[source controller documentation](https://github.com/kubernetes/ingress-nginx/blob/controller-v1.14.1/docs/user-guide/nginx-configuration/annotations.md)
and [F5 annotation reference](https://docs.nginx.com/nginx-ingress-controller/configuration/ingress-resources/advanced-configuration-with-annotations/).
The F5 class value is shown in its
[v5.6.3 class manifest](https://github.com/nginx/kubernetes-ingress/blob/v5.6.3/deployments/common/ingress-class.yaml).
These are syntax evidence, not recommended deployment versions or a cross-version compatibility
guarantee. Record the actual source and target image/chart versions and verify their contracts
before adapting the files.

## Worked Cutover Gates

Use this as an example decision record, replacing its thresholds with the application's measured
baseline and agreed SLOs. The synthetic role `migration-operator` must be assigned to a real,
authorized operator in the private operational record.

| Stage | Owner | Success threshold and observation | Stop condition | Traffic rollback |
| --- | --- | --- | --- | --- |
| Preview | migration-operator | Target has a current accepted event and no new rejection for 10 minutes; 100 representative requests meet the expected status/backend contract | Any wrong backend, certificate/auth failure, class collision or unaccounted default difference | Production still points to source; stop preview progression |
| Traffic switch | migration-operator | Prior DNS TTL has expired; use the reviewed DNS/provider change; observe at least 100 requests over 10 minutes | 5xx rises more than 0.1 percentage point above baseline, p95 exceeds 110% of baseline, or any correctness gate fails | Revert the recorded traffic-switch Git commit and reconcile the source destination |
| Retention | migration-operator | Keep source route/controller deployable for the agreed rollback window and verify renewal/monitoring | A late protocol, renewal or source-IP regression | Same traffic-switch reversal while the source remains available |

Before the switch, record the immutable source/target Git revisions, the exact traffic-switch
commit, old/new destinations, prior DNS TTL, baseline measurements, and rollback-window end.
If these fields or any compatibility-ledger row are unresolved, the plan is not executable.
DNS reversal is not instantaneous: caches and existing connections may still reach the target.
Keep both controllers available while verifying rollback; do not delete the target to force it.

Verify a request body size at the configured boundary and one byte above it using an approved
fixture backend that permits the accepted request. For this `8m` example, that means 8 MiB and
8 MiB plus one byte, with 413 for the rejected case. Use a controlled slow upstream to check
idle read/write behavior rather than interpreting a client-side request timeout as equivalent.
Do not send synthetic load or oversized bodies to a real service without approval.

## Verification and Cleanup Boundaries

Offline validation covers YAML, class identities, the exact intentional manifest differences,
and any relevant Helm rendering. It cannot establish NGINX configuration acceptance, protocol
behavior, certificate renewal, metrics or rollback readiness.

With live approval, require a fresh `AddedOrUpdated` event or equivalent accepted state, no new
rejections in the observation window, and requests directed to the target address with the intended
Host and TLS SNI. Keep certificate verification enabled. A populated Ingress status address or
an unauthenticated 401 alone is not sufficient evidence.

After switching traffic, keep the target resource's preview name through the rollback window;
renaming it is unnecessary for serving production traffic. Remove source routes and the source
controller only after dependency, DNS-cache and rollback gates pass. Preserve shared Services,
Secrets and certificate ownership. Use the
[full compatibility and rollout reference](../references/compatibility-and-rollout.md) for Basic Auth,
mergeable hosts, L4 listeners and other features deliberately absent from this narrow pair.
