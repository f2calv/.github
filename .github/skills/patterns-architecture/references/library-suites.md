# Capability Library Suite Review

Review the consumer-facing architecture, not a hypothetical application assembled from the packages.
Distinguish published libraries, testing-support libraries, test suites and executable hosts.
For .NET, use the [project inventory](../../dotnet-cleanup/references/project-inventory.md).

## Evidence and Consumer View

1. Inventory actual published artifacts, package/module identities, supported runtimes, dependencies
   and public namespaces. Verify declarations against shared build configuration and conditional
   items; apply language-specific metadata checks where relevant.
2. Read existing package/catalogue diagrams. Verify manifest edges and preserve maintained views
   rather than creating a second graph with the same purpose.
3. Show the suite as capabilities consumed by applications. Packages are not running containers;
   storage and network endpoints are dependencies chosen by consumers, not automatically owned
   infrastructure of the suite.
4. Build a code map of capabilities, public ports, implementations, registrations and dependencies.
   A role namespace such as `Services` can contain several capabilities; it is not a component.
5. Trace representative operations through registrations, public methods, constructors and actual
   dependency calls. Inspect API signatures for transitive framework/provider coupling.
6. Derive the proposed ownership map with the [namespace profiles](./namespaces.md), then the
   language-specific collision and metadata map. For .NET use the
   [.NET namespace reference](./dotnet-namespaces.md).
   Report source-discovery limitations instead of treating a lexical scan as compiler evidence.

## Boundary Questions

- Can a consumer use one capability without referencing unrelated runtime or UI dependencies?
- Are consumer contracts separated where doing so avoids server dependencies in frontend clients?
- Do concrete adapters depend on the capability contracts they implement, rather than the reverse?
- Is a public abstraction justified by real consumer use, substitution or an extension point?
- Does a broad utility package hide several unrelated change owners, or merely collect stable helpers?
- Where source is compiled into multiple artifacts, are generated code and public identities kept
  correct without introducing an unnecessary runtime dependency?
- Are public implementation types genuinely required by consumers or generators? No local references
  is not evidence that a released public type is safe to make internal.

Use the [architecture review](../../patterns-architecture-review/SKILL.md) for ratings and
proportionate findings. Cycles and leaked provider types need evidence; separate contracts,
shared role namespaces and multiple packages alone are not smells.

## Decisions and Repository Declaration

Separate metadata cleanup, public API migration and package-boundary changes. Recommend the
smallest effective change and include healthy boundaries and the cost of leaving an existing
published API unchanged.

A local declaration names architecture `capability-library-suite` and the chosen namespace profile,
links to [the shared skill](../SKILL.md), and lists only approved
repository-specific deviations. State whether that profile describes current code or an agreed
alignment target. Do not duplicate this review procedure in the local instructions.
