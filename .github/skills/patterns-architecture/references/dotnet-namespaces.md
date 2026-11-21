# .NET Namespace Profiles and Public Identity

The [generic namespace reference](./namespaces.md) owns profile selection. This reference supplies
.NET defaults and CLR, build and generated-code consequences.

## Flattened Public Library Roles

For public NuGet libraries, use `flattened-role-namespaces` with one deliberately chosen library
root and role buckets. It does not put every type directly in the root or flatten application modules.

| Public responsibility | Example namespace |
| --- | --- |
| Consumer contracts and extension points | `Example.Common.Abstractions` |
| DTOs, options and configuration records | `Example.Common.Models` |
| Services, providers, handlers and factories | `Example.Common.Services` |
| Registration and other extension methods | `Example.Common.Extensions` |
| Exceptions, converters, validators and constants | `Example.Common.Exceptions`, `.Converters`, `.Validators`, `.Constants` |

Package `Example.Common.Serialization.Json` can contribute extensions in
`Example.Common.Extensions`; its package name is not a namespace requirement. Group source files
by capability and role as needed without adding those capability folders to the public namespace.
Services subfolders retain their selected role namespace. Additional public role buckets need a
real responsibility rather than another package-name prefix.

File placement, type naming and extension-class restrictions remain with the
[C# instructions](../../../instructions/dotnet.csharp.instructions.md#files-and-types).
Namespace naming does not merge assemblies, grant access to internal types or enforce a boundary.

## Application Modules

Applications use `hierarchical-module-namespaces`, for example `Example.Catalog.Abstractions`
and `Example.Ordering.Services`. Role subfolders need not add further namespace levels.
Choose the application root and module granularity from the architecture views; do not force a
library's flattening profile onto a modular monolith.

## RootNamespace Is Not a C# Namespace Rewrite

Inventory these identities separately:

- Project name/path and package ID.
- Assembly name and CLR type identity, including the explicit C# namespace.
- Evaluated `RootNamespace`, imports, per-item overrides and generated namespaces.
- Embedded resource names, Razor components, localization and other generated artifacts.

`RootNamespace` supplies defaults to tooling and generators; it does not change explicit C#
namespace declarations. Published-library projects normally inherit the common library root.
An explicit override requires a verified generation/resource need, not just a matching project
filename. Do not remove an override until its generated outputs and consumers are understood.

For a namespace-only change, preserve package/assembly identities unless their migration is
separately approved. Conversely, a seemingly metadata-only root change can break resource lookup
or generated types even when all explicit C# namespaces remain identical.

## Collisions and Deliberate Exceptions

Before flattening, map each public top-level type to its proposed namespace, name and generic
arity across all co-installable packages. Inspect partial declarations, nested types and conditional
provider-linked source separately. Assembly separation does not prevent ambiguous consumer type
references when two assemblies expose the same fully qualified public name.

Also inspect extension-class names and overload resolution: registration classes with an identical
name or methods with indistinguishable receiver/signatures can collide after a move.

Apply the [generic collision decision](./namespaces.md#record-the-decision) to these measured
CLR/type and overload conflicts before choosing descriptive names, qualifiers or deferred migration.

Default to the flattened profile for new APIs and prevent avoidable duplicate names. Do not silently
add blanket provider/capability exemptions or rename released public types. An exception records
the affected symbols, evidence, consumer cost and why the smaller alternative is insufficient.
Framework-owned namespaces are not the default library root; existing contracts must be reviewed
against the C# restrictions rather than treated as precedent for new deviations.

## Safe Alignment

1. Audit every public package in scope and distinguish current conformance from the agreed target.
   A published testing-support library belongs in this inventory; test suites and hosts do not.
2. Trace actual references and public signatures using symbol tools where available. Regex inventory
   is discovery evidence, not proof of complete API identity or consumer compatibility.
3. Identify serialized type names, polymorphic discriminators, reflection/assembly scanning, resources,
   Razor code-behind, generated EF/AOT source, migrations and provider-linked types affected by a move.
   A namespace change alone is not proof that a database schema or wire format must change.
4. Agree the target map, collision handling and release strategy before edits. Namespace/type moves
   are public API changes even when binary package IDs stay fixed.
5. Separate file moves, root metadata and explicit public namespace migrations into independently
   verifiable phases. Update dependent call sites and generated artifacts together.
6. With approval, build all affected target frameworks, inspect public/generated/resource outputs,
   run relevant consumer and packaging checks, and exercise affected AOT/Razor/serialization paths.
   An ordinary build alone does not certify those paths.
7. Publish only through the approved versioned release process. Keep consumers on older immutable
   releases until they migrate; do not invent compatibility wrappers or pretend an assembly move
   forwards a renamed namespace.
