# Transport and Recovery Acceptance Cases

## A Deliberate Subscription Transport

This registration fragment targets managed .NET gRPC and assumes an existing generated
`Updates.UpdatesClient`, configuration and DI host. Package versions belong in the repository's
existing dependency management. The numerical budgets are an example to agree with the actual
server/proxy policies, not mandatory fleet-wide defaults.

```csharp
using Microsoft.Extensions.DependencyInjection;

builder.Services
    .AddGrpcClient<Updates.UpdatesClient>(options =>
    {
        options.Address = new Uri(builder.Configuration["Updates:GrpcAddress"]
            ?? throw new InvalidOperationException("Updates gRPC address is required."));
    })
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        ConnectTimeout = TimeSpan.FromSeconds(10),
        EnableMultipleHttp2Connections = true,
        KeepAlivePingDelay = TimeSpan.FromSeconds(60),
        KeepAlivePingTimeout = TimeSpan.FromSeconds(30),
        KeepAlivePingPolicy = HttpKeepAlivePingPolicy.WithActiveRequests
    });
```

No automatic mutation retry, authentication, application heartbeat, durable replay or load balancing
is added by this fragment. Configure those only from the actual contract. Keepalive applies to the
HTTP/2 connection, not a maximum stream lifetime. A responsive intermediary is not proof that its
upstream application is processing work.

Use a separate unary call budget, for example a deadline based on injected
`TimeProvider.GetUtcNow().Add(budget).UtcDateTime`, plus the caller's cancellation token. When
forwarding a parent RPC, propagate its tighter remaining deadline instead.

## A Supervised Reconnect Owner

Before implementing a loop, write down these transitions:

| Event | Required behavior |
| --- | --- |
| Host cancellation | Cancel active read/write and stop without retry |
| Graceful stream EOF | Complete if finite; otherwise bounded reconnect backoff |
| Transient transport failure | Record reason, dispose the call, back off and resume from agreed identity/cursor |
| Live transport but missing required application heartbeat | Cancel the call and surface a distinct progress-timeout reason |
| Authentication/configuration failure | Surface actionable failure; do not retry continuously |
| Contract mismatch | Apply an explicit bounded rollout policy; do not deserialize incompatible data |
| Duplicate consumer identity | Resolve ownership; never invent a random identity to bypass it |
| Inbound processing failure | Preserve acknowledgement/deduplication semantics and expose failure |

Both request and response tasks are owned, awaited and cancelled together. Do not discard a
`Task.Run` connection loop. The consumer either observes the task directly or receives a terminal
channel error/completion that its lifecycle owner supervises. Test that unexpected faults do not
turn into ordinary EOF.

## Regression Matrix

| Scenario | Exact acceptance evidence |
| --- | --- |
| Registration | Actual named gRPC primary handler has the agreed connect/ping settings; unrelated REST registration is unchanged |
| Half-open peer | Real loopback HTTP/2 peer accepts the connection and replies to setup/headers but stops answering pings; active RPC fails within the test budget without caller cancellation |
| Healthy idle stream | A peer answers pings while producing no messages; no spurious application-idle failure unless the contract requires heartbeat controls |
| Before response headers | Lost/unreachable peer is bounded by the relevant connect/call budget; do not assume a post-handshake test covers every connection phase |
| Application stall | Peer still answers pings, but heartbeat/progress or acknowledgement age breaches the agreed threshold; application supervision terminates it |
| Idle final acknowledgement | One delivery remains unacknowledged and no further data arrives; timeout still releases the subscriber identity |
| Duplex request EOF/fault | Response producer is idle; request-side termination cancels it and releases registry/budget resources |
| Reconnect | Unavailable and graceful EOF each reconnect without a tight loop; stable identity and resume point survive |
| Replay/retention | No unacknowledged item is pruned; duplicates do not repeat forbidden side effects |
| Overload | Full queue produces the agreed block/drop/reject behavior with observable counts and control-frame behavior |
| Snapshot/live handoff | Interleaved updates at the watermark are neither silently lost nor applied twice |
| Cancellation/disposal | Blocked reads/writes exit; calls, previous channels and background tasks are released across repeated attempts |
| Unary failure | Empty success, unavailable, deadline, unauthenticated and permission-denied remain distinguishable |
| Readiness replay | Consumer starts before a required tool/API Service is ready; bounded recovery works without a readiness cycle |
| Rollout | Graceful and abrupt server replacement preserve the documented delivery contract; no duplicate singleton owner |
| Contract evolution | Old/new serializers preserve supported fields and explicit incompatible-version behavior |

Accelerate keepalive timings only in isolated tests, and independently assert the production
registration's exact values. Keep the whole test bounded and verify timeout detection happened
before test cancellation. Validate the correct logical client: the gRPC factory's default name is
not necessarily `typeof(GeneratedClient).FullName`. Obtain it from the relevant
`IHttpClientBuilder.Name`, or use the explicit named registration.

Fake gRPC streams test protocol state machines, not socket liveness. In-process HTTP test servers
may bypass real HTTP/2 transport. A loopback fake that acknowledges every frame cannot reproduce a
black hole; assert that the expected ping was observed and intentionally left unanswered.
Kubernetes/ingress, TLS/mTLS, scale and real restart checks require separately approved environment
tests; passing loopback tests does not prove them.
