# Type Layout

The full file, folder, namespace and naming rules summarised in the
[C# instructions](../../../instructions/dotnet.csharp.instructions.md#files-and-types); the
Layout and Naming audits check them.

## Rules

- **One top-level type per file**, named after the type; only nested types share a file. Two
  exceptions: `_Enums.cs` holds every enum in the project and nothing else, and `_*Config.cs` (such
  as `_AppConfig.cs`) groups a configuration root with its related config types.
- Generic type filenames encode type parameters in braces: `Widget{T}.cs`, `Cache{TKey,TValue}.cs`.
- **Interfaces** start with `I`, live in an `Abstractions` folder and namespace, and name a role or
  capability (`IMessageGateway`), never an implementing class with an `I` prefix or a `Service`
  suffix. Rename an existing interface only when already changing it; that is a breaking change.
- **Remove single-implementation interfaces** unless tests substitute them, another assembly
  consumes them as a contract or extension point, or a second implementation exists. Never add one
  for a speculative future implementation.
- **Services** (DI-registered application types) live in `Services` with a `Service` suffix, or a
  more specific role suffix (`Handler`, `Factory`, `Manager`, `Coordinator`). Group supporting types
  in a `Services` sub-folder or `ServiceName.SubCategory.cs` partials. Types outside DI keep their
  role suffix (`Validator`, `Converter`).
- **Extension classes** live in `Extensions`, named after the extended type
  (`ServiceCollectionExtensions`), including endpoint-mapping and host-registration extensions. Never
  use a framework namespace such as `Microsoft.AspNetCore.Builder`; keep them to wiring and delegate
  behaviour to the owning service.
- **Models** (DTOs, payloads, options and configuration records) live in `Models`; EF Core entities
  follow the [EF Core instructions](../../../instructions/dotnet.efcore.instructions.md). **Custom exceptions** use the `Exception` suffix, one per file in
  `Exceptions/` with a `.Exceptions` namespace. Nested private test doubles stay with their test type.
- **Wire constants** (request URIs, route templates, header names) go in a `static class` per API
  surface under `Constants` (`RequestUris`, `UploadHeaders`), for APIs called and exposed alike.
- Namespaces follow folders, except that sub-folders of `Services` keep the `Services` namespace.
- Every project root has a `GlobalUsings.cs`; move a namespace imported by more than two files into
  it and delete the per-file duplicates, re-checking after refactors.
