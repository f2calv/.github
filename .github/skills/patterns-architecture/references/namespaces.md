# Namespace Ownership Profiles

Architecture and namespace shape are separate decisions. A hierarchy does not prove modularity;
flattening does not erase ownership when public APIs, visibility and dependencies remain deliberate.

## Choose the Profile

| Profile | Shape | Useful when | Main risk |
| --- | --- | --- | --- |
| `flattened-role-namespaces` | Shared consumer root followed by responsibility, without repeating package/capability names | Coherent library APIs benefit from common imports and role discovery | Public-name and extension-method collisions across co-installable packages |
| `hierarchical-module-namespaces` | Application root, owned module and optional role buckets | Application capabilities need visible ownership and independently understandable contracts | Folder-mirroring creates needless depth or hides cross-module dependencies behind names |

Prefer the smallest namespace that communicates API ownership. Namespaces need not repeat every
physical folder. They also do not replace visibility, dependency checks or deliberate public ports.

These are ownership profiles, not universal language syntax rules. Package-to-folder constraints,
import resolution, exported symbols and generated names differ by ecosystem; obey the actual
toolchain. Concrete .NET defaults and migration checks belong in
[.NET namespaces](./dotnet-namespaces.md), not a generic rule applied to every language.

## Record the Decision

1. Identify the consumer-facing root, capability owners and public symbols in scope.
2. Choose the profile alongside, not as a consequence of, the architecture profile.
3. Measure proposed-name collisions and inspect public, persisted and generated identities.
4. Compare a descriptive symbol name, a minimal justified qualifier and deferred migration.
   Do not silently invent blanket exceptions or change released APIs.
5. Declare the profile in repository instructions with a link to its owner. List only
   repository-specific deviations, their evidence and whether alignment is current or planned.

A modular application can contain a separately published helper library with a different namespace
profile. A library suite can expose an intentionally hierarchical public API where ownership or
collisions justify it; flattening is not permission to destroy an existing consumer contract.

For consequential public changes, agree the target, affected consumers and release strategy first.
Use the ecosystem's existing API, build and runtime checks with execution approval. Source-folder
moves and successful compilation alone are not evidence of public or generated compatibility.
