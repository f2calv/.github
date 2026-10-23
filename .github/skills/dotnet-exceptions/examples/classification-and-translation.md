# Exception Classification and Narrow Translation

Choose an exception by the failed contract and the consumer that must act on it, not by a blanket
replacement of every `throw`. These examples use synthetic import data and do not change any
application's public exception contract.

## Cases That Should Remain BCL or Protocol Exceptions

| Failure | Correct shape | Why no area exception |
| --- | --- | --- |
| Caller passes a null stream | `ArgumentNullException.ThrowIfNull(content)` | Caller broke a method precondition |
| Operation needs initialization first | `throw new InvalidOperationException("Initialize the reader before use.")` | Object state, not an import-format failure |
| Strict integer parsing fails | `int.Parse(text, CultureInfo.InvariantCulture)` surfaces `FormatException` | The method's contract is parsing; use `TryParse` for expected validation failure |
| A JSON converter rejects a token | `throw new JsonException("Expected an array.")` | The serializer's protocol boundary owns the error |
| Requested cancellation | Pass the token and let `OperationCanceledException` propagate | Cancellation must not become an application error |
| A user-entered value fails ordinary validation | Return the application's explicit validation result | Expected invalid input need not be exceptional |

Do not wrap these merely to make exception types uniform. Configuration errors belong in options
validation rather than ad hoc domain exceptions.

## When an Area Exception Helps

Assume an import subsystem already reports malformed documents as exceptions, and its application
boundary needs to reject malformed imports without also swallowing storage, configuration or
programming failures. That concrete consumer justifies an area type even with only two throw sites.
Without that consumer or a recurring failure area, retain the appropriate existing type.

The [exception template](../templates/ImportDocumentException.cs.tmpl) derives from the actual
`CasCap.Common.Exceptions.GenericException` supplied by `CasCap.Common.Extensions`. Use it only
where the solution already references that shared library; substitute the solution's established
base if different. A deliberately independent contracts/client package must not gain a shared-library
dependency just for this example.

Copy the template to `Exceptions/ImportDocumentException.cs`, replacing the synthetic namespace and
area name. Keep one type per file. All three constructors preserve the normal exception contract;
no serialization constructor or compatibility shim is needed.

## Before and After

A catch translating a parser failure previously used the undifferentiated domain base:

```csharp
catch (JsonException exception)
{
    throw new GenericException("The import document is not valid JSON.", exception);
}
```

The updated reader below changes that translated type while preserving its safe message and cause.
The root-shape failure uses the same area type. It does not catch argument, I/O or cancellation
exceptions. These complete file snippets target .NET 10 with nullable reference types and implicit
usings enabled; merge them into an existing project rather than adding another application.

### `Services/ImportReaderService.cs`

```csharp
using Example.Exceptions;
using System.Text.Json;

namespace Example.Services;

/// <summary>Counts records in an import document whose root must be an array.</summary>
public sealed class ImportReaderService
{
    /// <summary>Reads a document without taking ownership of the caller's stream.</summary>
    /// <param name="content">The readable import document stream.</param>
    /// <param name="cancellationToken">Cancels document reading.</param>
    /// <returns>The number of root array elements.</returns>
    public async Task<int> CountRecordsAsync(Stream content, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(content);
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            using var document = await JsonDocument.ParseAsync(content,
                cancellationToken: cancellationToken).ConfigureAwait(false);
            if (document.RootElement.ValueKind is not JsonValueKind.Array)
                throw new ImportDocumentException("The import document must contain an array.");

            return document.RootElement.GetArrayLength();
        }
        catch (JsonException exception)
        {
            throw new ImportDocumentException("The import document is not valid JSON.", exception);
        }
    }
}
```

### `Models/ImportResult.cs`

```csharp
namespace Example.Models;

/// <summary>Reports an accepted import count or an explicit document rejection.</summary>
/// <param name="Accepted">Whether the document was accepted.</param>
/// <param name="RecordCount">The count on success; null on rejection.</param>
/// <param name="ErrorCode">A stable public-safe code on rejection; null on success.</param>
public sealed record ImportResult(bool Accepted, int? RecordCount, string? ErrorCode);
```

### `Services/ImportService.cs`

```csharp
using Example.Exceptions;
using Example.Models;

namespace Example.Services;

/// <summary>Translates only known document failures into an explicit import result.</summary>
public sealed class ImportService(ImportReaderService importReaderSvc)
{
    /// <summary>Inspects a document while preserving unrelated failures and cancellation.</summary>
    /// <param name="content">The caller-owned document stream.</param>
    /// <param name="cancellationToken">Cancels the operation.</param>
    /// <returns>An accepted count or a document-specific rejection.</returns>
    public async Task<ImportResult> InspectAsync(Stream content, CancellationToken cancellationToken)
    {
        try
        {
            var count = await importReaderSvc.CountRecordsAsync(content, cancellationToken).ConfigureAwait(false);
            return new(true, count, null);
        }
        catch (ImportDocumentException)
        {
            return new(false, null, "invalid-document");
        }
    }
}
```

The caller can display or handle the explicit rejection; it must not turn it into an apparent
success with a zero count. For an existing application, preserve its established result and
notification contract rather than introducing this illustrative record alongside an equivalent.
Changing an established exception-based API into a result-based one is separate behavioral work:
this caller demonstrates an application boundary, not a mandatory library migration.

The outer exception message is safe to expose; the preserved inner exception can still contain
sensitive provider details. Never serialize or indiscriminately log the exception chain. This
minimal reader is not a full untrusted-file importer: retain the application's existing size,
format, authorization and resource limits around it.

## Validation Cases

With approval, compile against the actual shared base and test the exact snippets:

| Input or condition | Expected outcome |
| --- | --- |
| `[]` | Accepted, count `0`, no error code |
| `[1,2]` | Accepted, count `2`, no error code |
| `{}` | `ImportDocumentException` from reader; explicit rejection from application boundary |
| Invalid JSON | Same area type, retaining the original `JsonException` as `InnerException` |
| Null stream | `ArgumentNullException`, not a document rejection |
| Cancelled token or cancellation during reading | Cancellation escapes both reader and application boundary |
| Stream raises `IOException` | Original I/O failure escapes; it is not misclassified as malformed content |

Also exercise the parameterless, message and message-plus-inner constructors. When applying this
pattern to a published library, update callers and exception assertions together and document the
new public type through the normal release process; this example does not authorize that rollout.
