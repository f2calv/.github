# Reliability and Kubernetes

## Distinguish the Budgets

| Budget | Purpose | Enforcement |
| --- | --- | --- |
| Connect timeout | Bound opening a new transport connection | `SocketsHttpHandler.ConnectTimeout` |
| Finite RPC deadline | Bound one logical operation, including allowed retries | gRPC deadline plus caller cancellation |
| Transport liveness | Detect a peer/path that no longer responds to HTTP/2 | Keepalive ping delay/timeout, supported on every hop |
| Application progress | Detect a live HTTP/2 connection whose producer or consumer stopped work | Heartbeat/read watchdog or acknowledgement-age timer |
| Reconnect backoff | Bound repeated recovery attempts without flooding a dependency | Supervised loop, capped backoff/jitter and host cancellation |
| Shutdown grace | Bound stopping admission and completing/cancelling active work | Host timeout and Kubernetes termination budget |

HTTP/2 pings acknowledge the transport, not a business message. They cannot prove producer hydration,
tool readiness, cursor progress or successful downstream processing. Proxies can answer pings
without proving the application behind them is healthy.

Finite unary calls need explicit deadlines. Propagate the tighter parent deadline and cancellation
into downstream RPC/database/HTTP calls. `EnableCallContextPropagation()` is appropriate for clients
called inside gRPC services; configure deliberately when the same registration is also used outside
a gRPC context. Do not hide a missing context with a broad cancellation catch.

An intentionally unbounded subscription still needs host cancellation, transport detection and,
when required, application progress detection. Do not periodically kill a healthy long-lived stream
as a substitute for liveness.

## Channels, Keepalive and Retries

Prefer `AddGrpcClient` for centrally registered generated clients, with factory-managed handlers
and channels. An explicitly owned reusable `GrpcChannel` is also valid when its lifecycle and
credentials are clear. Reconnecting a call does not generally require constructing a fresh channel.
If a fresh channel is necessary, dispose the old attempt's channel on every path.

Generated clients are lightweight and can share a channel. Review scoped interceptors and dynamic
credentials independently; do not store request-scoped authentication state in a shared interceptor.
Factory lifetime rotation does not forcibly retire a channel already held by an active stream.

Choose keepalive jointly with server, ingress and mesh policies. Aggressive unsolicited pings can
cause `GOAWAY`/`too_many_pings`. Prefer active-request pings for subscription clients; avoid pings
on unused pooled connections unless explicitly needed. Preserve the factory's multiple-HTTP/2
connection behavior when replacing its primary handler. Configure message sizes in both directions,
flow-control windows and connection concurrency from actual workload limits, not unlimited values.

Do not stack generic HTTP retries/timeouts on top of gRPC method retries and an application reconnect
loop. Read the effective policy at every layer. Use bounded, per-method gRPC retries only where the
RPC is safe to replay. Respect total deadlines; treat cancellation, permission/configuration errors
and version mismatches separately from transient unavailability.

A streaming call can become committed when headers arrive, before useful data. Built-in retry
does not resume a committed stream. Reconnection must preserve filters, stable identity, cursor,
deduplication and single-owner rules. An uncertain mutation is not proof of failure: reconcile
rather than automatically replaying it.

## HTTP/2, TLS and Routing

Trace client -> Service/proxy -> targetPort -> listener -> mapped service.

- For cleartext h2c, configure the Kestrel RPC listener as HTTP/2-only. TLS permits HTTP/1.1 and
  HTTP/2 negotiation through ALPN. Do not infer either from an `EXPOSE` line or port name.
- Prefer TLS with verified authority/certificates, or an explicitly protected mesh transport.
  Plaintext within a trusted network is a documented boundary, not authentication.
- Verify both proxy legs: downstream HTTP/2 alone does not prove upstream gRPC support. Check
  ingress-controller-specific annotations/resources, TLS mode, trailers, buffering, message/body
  limits and idle/read/stream duration timeouts. Do not copy one controller's annotations to another.
- Never disable certificate validation as a workaround. Do not assume an HTTP Basic/bearer helper
  sends credentials over h2c; inspect its actual scheme restrictions and intended trust boundary.

## Discovery and Load Balancing

| Topology | Behavior and limits |
| --- | --- |
| ClusterIP Service | A TCP connection selects a backend; multiplexed calls may remain pinned to it |
| Headless Service plus DNS resolver | Exposes pod addresses; requires intentional client resolver, refresh and balancing policy |
| HTTP/2-aware L7 proxy/mesh | Can distribute independent RPCs, but adds another timeout/health/TLS boundary |

For .NET client-side balancing, use the gRPC DNS resolver (for example
`dns:///example-service.example-namespace.svc.cluster.local:5001`) plus explicit credentials and a
service-config balancing policy such as round-robin where appropriate. A headless Service alone
does not enable round-robin; pick-first is the default. Verify DNS refresh and new-pod discovery.

Neither round-robin nor `EnableMultipleHttp2Connections` redistributes messages inside an established
stream. A hot single stream needs application partitioning or multiple explicitly owned streams.

Do not load-balance a process-local subscriber registry as if it were distributed coordination.
Durable database cursors do not, by themselves, prevent duplicate live ownership across pods.
Keep receive-owner singleton constraints and rollout non-overlap enforced until ownership moves
to a deliberate distributed mechanism.

## Probes, Startup and Rollout

Separate:

- **Startup:** initialization can finish within its budget.
- **Liveness:** this process is not irrecoverably stuck; do not fail it merely for a remote outage.
- **Readiness:** this endpoint/role can currently serve the traffic routed to it.
- **Progress:** subscription connected, producer ready, last heartbeat age, oldest unacknowledged
  message, queue age and cursor lag, interpreted against expected workload activity.

HTTP health endpoints are valid operational surfaces, but an always-healthy HTTP handler cannot
prove the HTTP/2 port, service mapping or subscriber is working. Use the standard gRPC health
protocol where useful (`Grpc.AspNetCore.HealthChecks`, registered and mapped), with separate service
names/check predicates for roles. Do not add the package without wiring checks and probes.

Kubernetes native gRPC probes require the standard health service and a numeric port, not a named
port. The portable baseline is plaintext without application authentication; verify the actual
cluster version/feature gates before relying on newer TLS probe extensions. Keep health exposure
within an appropriate network boundary. A TCP probe only verifies that a socket can open.

Prefer startup probes plus meaningful readiness over long fixed initial delays. Readiness removes
unready pods from new Service routing; it does not gate background workers or terminate existing
streams. Check for a consumer whose tools/API are served by its own unready Service: replay can
start before tool discovery is routable. Gate required dependencies or recover discovery within a
bounded budget without creating a circular readiness dependency.

During shutdown, stop admission, signal unready/draining, propagate stopping cancellation, drain or
abort active calls, persist accepted cursors and await workers within the chosen host timeout.
Endpoint withdrawal and process stopping are concurrent Kubernetes events, not a strict sequence.
Include any `preStop` time in `terminationGracePeriodSeconds`; a fixed sleep alone is not draining.
PDBs and rolling settings address different availability/ownership concerns and neither provides
stream replay.

## Diagnostics and Management Alignment

Define one configurable transport profile only for clients with the same tested contract. Keep
unary and streaming profiles distinct where necessary. Avoid repeated hardcoded channel builders,
but do not extract domain-specific filters, replay policy or owner selection into a transport helper.

Expose safe service/method/status/duration metrics and trace correlation. Add stream connect,
reconnect reason, last-frame/progress age, queue depth/drops, outstanding age, cursor lag and replay
counts as appropriate. Standard gRPC duration metrics alone cannot identify a forever-open idle
subscription. Treat an absent metric differently from a confirmed zero.

Incident order:

1. Correlate artifact version and UTC/local timestamps without logging payloads.
2. Confirm upstream receipt and persistence using counts/sequences, not message bodies.
3. Compare active connections, durable cursors, queue/ack budgets and health.
4. Inspect both stream directions and actual reconnect logs; do not infer connection from pod Ready.
5. Check endpoint readiness, DNS, service routing and proxy transport separately.
6. Obtain permission before restarting a consumer: durable replay can cause real side effects.
7. Verify recovery with cursor advancement and completed downstream work, then separately verify
   a fresh request. A replay during startup may fail for a different protocol/dependency reason.

## Sources

Official guidance checked on 2026-10-25; recheck the deployed runtime and Kubernetes versions:

- [.NET gRPC performance and keepalive](https://learn.microsoft.com/en-us/aspnet/core/grpc/performance?view=aspnetcore-10.0)
- [Client factory and context propagation](https://learn.microsoft.com/en-us/aspnet/core/grpc/clientfactory?view=aspnetcore-10.0)
- [Deadlines and cancellation](https://learn.microsoft.com/en-us/aspnet/core/grpc/deadlines-cancellation?view=aspnetcore-10.0)
- [Retry commitment and streaming limits](https://learn.microsoft.com/en-us/aspnet/core/grpc/retries?view=aspnetcore-10.0)
- [DNS discovery and client-side balancing](https://learn.microsoft.com/en-us/aspnet/core/grpc/loadbalancing?view=aspnetcore-10.0)
- [Kestrel HTTP/2 and TLS](https://learn.microsoft.com/en-us/aspnet/core/grpc/aspnetcore?view=aspnetcore-10.0)
- [.NET gRPC health checks](https://learn.microsoft.com/en-us/aspnet/core/grpc/health-checks?view=aspnetcore-10.0)
- [Kubernetes probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Kubernetes pod termination](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#termination-of-pods)
- [gRPC diagnostics](https://learn.microsoft.com/en-us/aspnet/core/grpc/diagnostics?view=aspnetcore-10.0)
