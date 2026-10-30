---
name: dotnet-http-integrations
description: 'Create, refactor, audit or troubleshoot outbound .NET HTTP integrations: IHttpClientFactory, typed/named clients, delegating handlers, authentication, token refresh, resilience, retries, idempotency, timeouts, streaming, pagination and fake-handler tests. Use for external REST/HTTP clients, not gRPC or inbound controller/OpenAPI design.'
argument-hint: '[apply|audit|diagnose] [client or integration]'
user-invocable: true
---

# .NET HTTP Integrations

Give each external API a deliberate transport, failure and replay contract instead of scattering
HTTP calls or wrapping every failure in an unbounded retry.

## Authorities and Resources

- The [C# instructions](../../instructions/dotnet.csharp.instructions.md) own everyday HTTP,
  cancellation, disposal, errors and logging; the
  [configuration instructions](../../instructions/dotnet.configuration.instructions.md) own options
  and secrets. Follow [DI](../dotnet-dependency-injection/SKILL.md) for client/handler lifetimes.
- Load [resilience and contracts](./references/resilience-and-contracts.md) for retry/authentication
  decisions, and the [safe client example](./examples/safe-read-and-mutation.md) for wiring and
  fake-handler acceptance cases.
- Use [ports/adapters](../patterns-ports-and-adapters/SKILL.md) for external contract boundaries,
  [.NET Web API](../dotnet-webapi/SKILL.md) for inbound endpoints,
  [.NET gRPC](../dotnet-grpc/SKILL.md) for HTTP/2 RPC clients and streaming recovery,
  [REST Client requests](../tooling-rest-client/SKILL.md) for manual request files and
  [performance](../dotnet-performance/SKILL.md) for measured transport hot paths.
- Official [factory documentation](https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory)
  and [HTTP resilience](https://learn.microsoft.com/en-us/dotnet/core/resilience/http-resilience)
  are the API authorities; check the consumer's package version.

## Workflow

1. In `audit`/`diagnose`, report without edits. For implementation, trace existing client helpers,
   registrations, package versions, callers and tests before adding or replacing a client.
2. Record base-address source, allowed destinations, authentication and token lifecycle, operations,
   request/response limits, pagination, quotas and upstream error semantics. Verify current official
   upstream guidance when correctness depends on replay or access policy; never send private
   payloads or identifiers to web research tools.
3. Choose typed clients for cohesive API surfaces or named clients for long-lived consumers creating
   clients per operation. Do not capture transient typed clients in singletons or recreate raw
   sockets per request. Share existing transport helpers without moving application policy into them.
4. Map cancellation, total deadline, per-attempt timeout, concurrency/rate limits and retry policy.
   Ask before changing mutation replay, partial-success handling or externally visible timing.
5. Add one intentional resilience pipeline. Apply retry/idempotency and handler-order rules from
   the reference; inspect global defaults so local wiring does not silently stack retries.
6. Implement bounded serialization/deserialization, status/error translation, paging and resource
   ownership. Preserve upstream absence versus failure versus incomplete results; never convert
   transport errors into an empty collection or apparent success.
7. Wire callers, DI, selected-role validation, configuration examples and fake-handler tests
   together. Exclude authorization headers, signed URLs, user content and identifiers from diagnostics.

## Validation and Reporting

With approval, use isolated fake `HttpMessageHandler` tests and existing client fixtures first.
Assert exact method/path/headers without logging secret values; cover transient errors, permanent
errors, malformed payloads, missing fields, cancellation, attempt counts, timeout budgets, token
refresh races, pagination termination and disposal.

Mutation tests must assert side-effect/attempt counts, not just the final HTTP status. Verify
request content is replayable when retry is authorized. Live credentials, public endpoints and
load/soak tests require separate authorization; a fake transport is not upstream conformance proof.

For authorized live reads, exercise the production client from the intended workload's identity
and network. Consume the bounded response body and verify applicable revision conditions; matching
local credentials, response headers or opening a lazy SDK stream alone do not prove deployed
content access.

Report behavior changes, timeout/retry budgets, error mapping, tests run and external assumptions
not verified. Do not introduce a new client framework for a single ordinary integration.

## Maintaining This Skill

Apply the shared [customization feedback loop](../../instructions/workflow.instructions.md#maintaining-conventions)
when using this skill; the triggers below include newly learned topics, not only version drift.

- Incorporate verified transport, authentication or replay lessons into the relevant workflow/reference;
  extend the worked example and scripted-handler cases without generalizing one provider's policy.
- Recheck resilience defaults/APIs, handler scopes and factory lifetime guidance on package upgrades.
- Update examples when upstream idempotency, pagination, authentication or rate-limit policy changes.
- Keep inbound HTTP and manual request-file procedures in their linked authorities.
