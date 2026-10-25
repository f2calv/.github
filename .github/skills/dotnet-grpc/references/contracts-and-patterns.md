# Contracts and Delivery Patterns

## Contract Ownership

| Approach | Maintain | Verify |
| --- | --- | --- |
| Proto-first | Versioned `.proto` source and generated client/server artifacts owned by the contract package | Package/service identity, `GrpcServices` generation scope, imports and old/new peers |
| protobuf-net code-first | Explicit service names and stable numbered data members in the shared contract | Generated schema, serializer presence/default behavior, method routing and supported signatures |

Do not migrate between approaches just to standardize syntax. The inspected application patterns
use proto-first contracts; code-first is a supported design option, not evidence of its use.
Generate only the client/server code the delivery unit needs. `GrpcServices="Both"` is appropriate
when that assembly genuinely owns both roles, not a reason to couple every consumer to the host.

For proto-first, never reuse removed field numbers or names; add `reserved` declarations.
Additive wire compatibility does not guarantee application compatibility: test presence, zero/default
values, unknown enums, `oneof` changes, units, precision, timestamp/decimal mappings and semantic
version negotiation. Package names are wire identity, not just C# namespaces.

For code-first, keep `[ProtoMember(n)]` or `[DataMember(Order = n)]` stable. Audit explicit
`[Service]`/`[ServiceContract]` and method names before a CLR rename. Avoid inferred numbering and
object graphs with cycles. Check the supported protobuf-net version rather than assuming the
generated-client APIs or all interceptors have identical behavior.

Protocol enums use protobuf's numeric wire contract; JSON string-enum conventions do not rewrite it.
Do not serialize EF entities, runtime credentials, framework exceptions or arbitrary polymorphic
application objects as a public RPC model.

## Choose the Stream's Meaning

| Meaning | Suitable behavior | Do not promise |
| --- | --- | --- |
| Latest-value telemetry | Explicit coalescing or bounded dropping, freshness/gap counters | Every observation was processed |
| Ordered live events | Bounded admission, sequence/gap detection and stated resubscription behavior | Reconnect recovers items absent a replay source |
| Durable work delivery | Persist before delivery, stable consumer identity, ordered durable acknowledgements and retention | Exactly-once side effects without consumer idempotency |
| Snapshot plus live changes | Snapshot revision/watermark, buffering and deduplication at the handoff | Independent snapshot and stream calls are automatically gap-free |
| Finite replay/backtest | Backpressure, explicit start/end/progress controls, deterministic ordering | Production loss policy is acceptable for replay |

Keep control frames observable. If heartbeats, readiness and data share a dropping queue, determine
whether a lost control frame can change processing correctness. Separate control state where
necessary or make it repeatable/versioned; expose dropped-item counts and sequence gaps.

## Reusable Application Patterns

These patterns are derived from inspected streaming applications without importing their domain
types, private deployment coordinates or incident payloads.

- **Feature-selected endpoints:** register and map the same enabled role. A disabled method should
  be absent, not mapped to an implementation whose dependencies were never registered.
- **Separate cleartext listeners:** HTTP control/health traffic and HTTP/2 RPC traffic have distinct
  listeners and Service mappings; test both. Shared encrypted listeners are a separate valid design.
- **One fast ingress owner:** a transport read loop only admits to a bounded queue; expensive
  resolution, storage and downstream operations happen outside it.
- **Persist then fan out:** durable messages precede subscriber notification. A wake-up channel can
  coalesce notifications because the durable store, not the notification, owns the backlog.
- **Stable consumer identities:** independent cursors and server-side routing permissions belong to
  logical consumers, not random process or pod identities. Enforce duplicate ownership across the
  actual serving topology, not merely one process.
- **Acknowledge processed work:** acknowledge only after the consumer's accepted processing boundary.
  Document whether enqueueing or completed side effects count as processing; reconnect can redeliver.
- **In-band stream controls:** explicit started/heartbeat/ready/exhausted controls can distinguish a
  sparse healthy producer from a stalled application and detect incompatible protocol versions.
- **Separate finite bootstrap from live subscription:** a bounded snapshot RPC and a long-running
  feed need different deadlines; define revision/cursor handoff if continuity matters.
- **Explicit overload modes:** lossless finite replay and freshness-oriented live feeds can have
  different bounded admission policies, but that is an application decision, not a transport default.

## Acknowledgements and Termination

An outstanding-message limit bounds memory and admission. It is not an acknowledgement deadline
unless a timer independently expires the oldest outstanding delivery. A timer checked only when
the next write exhausts capacity cannot detect an unacknowledged final message on an idle stream.

Validate delivery identities, ordering and monotonic cursor movement. Do not advance past
unprocessed work; account for messages intentionally excluded by server-side routing. Coordinate
cursor updates and retention so the required replay window survives reconnect.

Duplex request EOF is a lifecycle event even when no data is being produced. Own and await the
read and write tasks, use linked cancellation throughout, cancel the sibling on terminal failure,
and release the registry entry and resources on every exit. Logging an acknowledgement-reader
exception does not stop a delivery loop still waiting on a separate token.

gRPC permits independent reading and writing, but not concurrent unsynchronized writes to the same
stream. Finish owned tasks before returning the server method or disposing a client call.

## Error and Privacy Contracts

Map validation, authentication, authorization, conflict, missing resource, deadline and unavailable
dependency to deliberate gRPC statuses. Keep expected absence different from transport failure.
Do not convert every `RpcException` into `null`, an empty list or `false` unless a documented typed
outcome separately preserves the failure category.

Detailed server exceptions and trailers can disclose internal state. Log safe categories and
correlation identifiers; exclude bodies, user names, account/group identities, credentials and raw
metadata. Keep cardinality bounded by service/method/status, not request or subscriber identities.

## Sources

- [Protocol Buffers proto3 guide](https://protobuf.dev/programming-guides/proto3/)
- [protobuf-net.Grpc contract definitions](https://grpc.protobuf-net.dev/gettingstarted)
- [.NET gRPC versioning](https://learn.microsoft.com/en-us/aspnet/core/grpc/versioning?view=aspnetcore-10.0)
- [.NET gRPC error handling](https://learn.microsoft.com/en-us/aspnet/core/grpc/error-handling?view=aspnetcore-10.0)

Consult current package documentation before applying signatures or compatibility assumptions.
