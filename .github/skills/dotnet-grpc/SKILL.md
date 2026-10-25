---
name: dotnet-grpc
description: 'Create, refactor, audit or troubleshoot .NET gRPC clients, servers and Protocol Buffers contracts: proto-first and protobuf-net code-first, HTTP/2 and h2c, channel lifetimes, deadlines, cancellation, keepalive, retries, streaming acknowledgements and replay, Kubernetes discovery, load balancing, probes, rollout and observability. Use for GrpcChannel, AddGrpcClient, AddGrpc, MapGrpcService, .proto and gRPC-backed workers; not REST/OpenAPI, SignalR or HTTP MCP tools.'
argument-hint: '[design|apply|audit|diagnose] [contract, client, service or workspace]'
user-invocable: true
---

# .NET gRPC

Treat gRPC as a versioned RPC and delivery contract over HTTP/2, not a synonym for every internal
API. Trace the actual protocol before changing transport settings.

## Authorities and Resources

- [gRPC instructions](../../instructions/dotnet.grpc.instructions.md) own the scoped invariants;
  [C# instructions](../../instructions/dotnet.csharp.instructions.md) own types, cancellation,
  disposal, errors and logging.
- Read [contracts and delivery patterns](./references/contracts-and-patterns.md) for schema
  ownership, streaming guarantees, acknowledgements and reusable application patterns.
- Read [reliability and Kubernetes](./references/reliability-and-kubernetes.md) for transport
  budgets, discovery, load balancing, health, draining and incident triage.
- Use [transport and recovery acceptance cases](./examples/transport-and-recovery.md) to wire
  clients and verify actual failure/recovery behavior.
- Use [DI](../dotnet-dependency-injection/SKILL.md) for lifetimes,
  [background pipelines](../dotnet-background-pipelines/SKILL.md) for bounded queues and supervision,
  [HTTP integrations](../dotnet-http-integrations/SKILL.md) for REST adapters,
  [Web API](../dotnet-webapi/SKILL.md) for controllers,
  [Helm](../helm-charts/SKILL.md) for chart mechanics and
  [container images](../container-images/SKILL.md) for packaging.
- Ask before executing tests or live calls; audits do not authorize deployments, restarts, replica
  changes, migrations, package publication or history rewrites.

## Workflow

### 1. Establish Scope and Evidence

1. Resolve the active workspace folders; exclude generated output, vendored code and duplicate
   dependency checkouts. A workspace review does not include every sibling clone.
2. Inventory `.proto`, `<Protobuf>`, generated-client registrations, `GrpcChannel`, `AddGrpcClient`,
   `AddGrpc`, `MapGrpcService`, protobuf-net service/data attributes and all client call sites.
   Distinguish managed `Grpc.Net.Client` from the retired native `Grpc.Core` transport:
   using `Grpc.Core` API types alone is not a native-transport dependency.
3. Record framework/package versions, contract owner, proto-first versus code-first, generated
   server/client ownership, runtime roles, configuration precedence and deployed artifact versions.
   Do not assume the source checkout is the running image.
4. Trace each method end to end: unary/server/client/bidirectional streaming, authority, actual
   listener, caller, state owner, authorization, deadline, cancellation, side effects and errors.
   Identify HTTP/MCP/SignalR boundaries rather than diagnosing them as gRPC failures.
5. For an audit, make no application edits. For implementation, inspect existing shared helpers
   and named-client conventions before adding another transport abstraction or dependency.

### 2. Define the Contract

1. Preserve established proto-first or code-first ownership unless a migration is requested.
   Keep wire messages separate from EF entities and private application configuration.
2. Record service/method names, package/version, field numbers and wire types, presence semantics,
   enum unknown/default handling, message limits, status mapping and old/new rollout compatibility.
3. Classify methods as read-only, idempotent or ambiguous mutation. Choose retry permission per
   method; an RPC name or an HTTP POST carrying gRPC is not proof of replay safety.
4. For streams, explicitly choose snapshot/latest-value versus durable-event semantics. Record
   ordering, bounded capacity/drop policy, acknowledgement point, replay/retention, resume identity,
   duplicates and single-owner versus competing/broadcast consumers.
5. Keep application-specific policy local. Extract common transport wiring only when consumers
   share the same tested behavior; do not create a generic stream framework for unrelated contracts.

### 3. Wire Reliable Clients and Servers

1. Reuse factory-managed handlers/channels or an explicitly owned long-lived channel. Track
   disposal and credential/interceptor scope; do not create a channel per message or assume
   transient generated clients imply transient sockets.
2. Define separate budgets for connection establishment, finite RPC deadline, HTTP/2 liveness,
   application acknowledgement/progress and shutdown. Infinite subscription lifetime is not
   permission for infinite failure detection.
3. Propagate request/host cancellation and the tighter parent deadline into downstream calls.
   Do not apply a unary timeout/retry handler indiscriminately to a long-lived stream.
4. Choose bounded per-method retries only where side effects permit. A committed streaming call
   requires application reconnection and resume; retry policy and keepalive do not implement replay.
5. Verify HTTP/2 on every hop, TLS/h2c and proxy behavior, request/response size limits, compression,
   auth/status handling and disabled-role endpoint behavior.
6. Supervise both directions of a duplex stream. End-of-stream, cancellation, acknowledgement-reader
   failure and writer failure must have an explicit shared termination path; observe and await all
   owned tasks.

### 4. Align Kubernetes Operations

1. Trace Service port/targetPort to the actual Kestrel listener; inspect rendered charts, not just
   values. Confirm any proxy supports gRPC upstream HTTP/2 and stream timeout budgets.
2. Choose connection-level ClusterIP routing, headless-DNS client-side balancing, or an HTTP/2-aware
   proxy deliberately. A long-lived stream stays with one backend; adding replicas does not move it.
3. Respect state ownership. In-memory subscriber registries and one receive owner are not made
   horizontally safe by adding round-robin or a second pod.
4. Distinguish startup, liveness, readiness and subscription progress. An HTTP 200 is not proof that
   gRPC works, a subscriber is connected, or an acknowledgement cursor is advancing.
5. Coordinate background consumption with dependencies that must be routable, including tool/API
   surfaces hosted in the consumer itself. Avoid readiness cycles; use bounded discovery recovery
   and observable admission gates rather than arbitrary startup sleeps.
6. Align endpoint withdrawal, host stopping, stream cancellation/drain, cursor persistence, rollout
   overlap and termination grace. Test both graceful rollout and abrupt/network-isolated loss.

### 5. Validate and Report

With approval, run the smallest existing contract/transport/consumer tests. Use isolated in-memory
fixtures for application logic and real loopback HTTP/2 for transport claims; a fake client cannot
prove ALPN, keepalive, proxy, socket or Kubernetes behavior.

Report:

- Coverage and exclusions; implemented patterns versus proposed alignment.
- Findings ranked by user impact, with exact source links and causal evidence. Distinguish a
  confirmed defect from a conditional scaling risk or an untested operational assumption.
- Configured limits and measured outcomes; actual test count, skips and blocked validation.
- Source changes versus published packages, deployed images and outstanding consumer propagation.

Keep private workspace findings in the session report or an approved private destination. Shared
guidance and examples must remain generic; do not publish private repository identities, hosts,
accounts, messages, deployment coordinates or incident logs.

## Maintaining This Skill

- Recheck gRPC/.NET HTTP/2 defaults, factory registration names and supported handlers on upgrades.
- Revisit Kubernetes probe/version limits, DNS resolver behavior and ingress/mesh timeout semantics.
- Extend fault-injection cases when a stream, acknowledgement, readiness or rollout failure reveals
  a distinct lifecycle gap; do not turn one incident's timing into a universal policy.
- Keep contract evolution, transport liveness and application progress distinct as helpers evolve;
  remove duplicated gRPC procedures from neighboring skills in favor of links here.
