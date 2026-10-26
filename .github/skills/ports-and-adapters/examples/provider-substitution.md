# A Document Lookup Port With Honest Substitution

A synthetic application needs a bounded document lookup. One adapter calls HTTP; another is a fake
used by application tests. This example illustrates an outbound port, not a universal storage
framework or a compiled fixture.

## Application-Owned Contract

In the application's `Abstractions` namespace, the contract could be:

```csharp
/// <summary>Looks up a document within the caller's authorized tenant.</summary>
public interface IDocumentLookup
{
    /// <summary>Returns the current document, or null for an authorized missing document.</summary>
    public Task<DocumentSummary?> FindAsync(
        DocumentLookupRequest request,
        CancellationToken cancellationToken
    );
}
```

`DocumentLookupRequest` and `DocumentSummary` are application DTOs in its `Models` namespace,
with normal XML documentation in their own files. The request contains a trusted tenant scope and
document key, not an HTTP URL or SDK object. The summary contains the required fields and revision,
not a provider response or deferred query.

`null` means an authorized missing document only. Authentication, timeout, invalid upstream data
and service failure do not return null. Input authorization is established by the application's
trusted boundary and enforced by tenant-scoped adapter access, not by trusting an arbitrary body field.

## Dependency and Mapping

| Component | Depends on | Does not depend on |
| --- | --- | --- |
| Application policy | Lookup contract and DTOs | HTTP SDK, status codes, provider configuration |
| HTTP adapter | Application contract and transport client | Controller/CLI implementation |
| Inbound HTTP/CLI adapter | Application use case | Outbound adapter internals |
| Host | Application and selected adapter registration | Business policy in registration factories |

The HTTP adapter maps recognized upstream not-found to null, success to a validated summary and
other outcomes to the existing safe error contract. The application decides what a missing
document means for the use case; the adapter does not create one automatically.

Do not add a `SaveAsync` method for a hypothetical future write consumer. If a real write use case
appears, define its revision/idempotency/commit semantics rather than assuming lookup semantics
are enough.

## Shared Contract Cases

| Case | HTTP adapter / fake expectation |
| --- | --- |
| Existing authorized document | Required fields and revision match contract |
| Missing document | Null, not fabricated empty content |
| Another tenant has the same key | No cross-tenant result |
| Caller cancellation before lookup | Operation observes cancellation |
| Dependency unavailable | Explicit failure, never null |
| Invalid response fields | Protocol/validation failure, not a partially populated summary |

The fake exposes controlled failures and revisions so application tests can exercise these cases.
It does not prove HTTP serialization, credentials, retry behavior or upstream freshness.
Run the HTTP adapter's mapping tests against a scripted handler, and provider conformance only
with approved isolated resources.

When extracting this seam from an existing client, first preserve the current behavior with
focused tests, then change consumers and registration together. Do not claim the whole application
is hexagonal merely because this port exists.
