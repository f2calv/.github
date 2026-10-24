# A Safe Read and a Deliberate Mutation

A synthetic catalog integration lists records and submits an export request. The upstream has no
documented idempotency guarantee for export submission. These are .NET registration fragments and
test specifications, not a complete or executed API client.

## Register One Pipeline

```csharp
services.AddHttpClient<CatalogClient>((provider, client) =>
{
    client.BaseAddress = provider.GetRequiredService<IOptions<CatalogOptions>>().Value.BaseAddress;
    client.Timeout = Timeout.InfiniteTimeSpan;
})
.AddStandardResilienceHandler(options =>
{
    options.Retry.DisableForUnsafeHttpMethods();
});
```

This fragment uses `Microsoft.Extensions.DependencyInjection`, `Microsoft.Extensions.Options`
and `Microsoft.Extensions.Http.Resilience`, with the resilience package managed through the
repository's existing package policy. `CatalogClient` and `CatalogOptions` are application types.
Validate the configured HTTPS destination and permitted host at startup; no real endpoint is embedded.
Confirm that global HTTP defaults have not already added a resilience handler.

The pipeline owns configured request/attempt timeouts here; infinite `HttpClient.Timeout` is not
an infinite operation allowance. Set and test total/attempt budgets for the application's needs.
If reading streamed bodies, the caller additionally supplies a deadline covering body consumption.

## Operation Contract

| Operation | Contract |
| --- | --- |
| GET bounded record page | Transient failures may retry within the overall budget |
| POST export request | At most one transport attempt from this pipeline; no automatic POST retry |
| POST timeout | Unknown outcome; expose reconciliation information through the established error contract |
| GET malformed payload | Explicit protocol failure, never an empty page |
| GET next page fails | Report failure or an explicitly typed partial result, not a complete collection |

Disabling retry does not remove circuit-breaking/timeouts, prevent caller resubmission or establish
exactly-once effects. The export workflow must also inspect outer retries and authentication replay.
If the upstream later offers idempotency keys, verify its scope/retention/conflict behavior before
changing this policy.

## Fake-Handler Acceptance Cases

| Scripted transport behavior | Required assertion |
| --- | --- |
| GET 503, then 200 | Bounded retry count and correct final DTO |
| POST 503 | One attempt; explicit failure |
| POST accepts then simulated timeout | No automatic resubmission or “definitely not created” claim |
| 401 while credentials expire concurrently | Refresh is coordinated; replay follows the selected operation policy |
| Response body never completes | Body deadline cancels and resources are released |
| Successful status with invalid JSON | Explicit deserialization/protocol failure; response disposed |
| Repeated next-page token | Paging stops with a diagnosed protocol error |
| Continuation targets another host | Rejected without forwarding credentials |
| Two user contexts use the same handler pool | No identity/header leakage |

Use a scripted handler and fake time where existing tooling supports it. Retain only safe attempt
metadata in test output. No real credentials, upstream calls or claims of live compatibility are
part of this example.
