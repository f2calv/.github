---
name: dotnet-aot
description: 'Assess, implement and validate .NET Native AOT for libraries, workers, CLIs and ASP.NET Core services on .NET 10 and 11. Use for PublishAot, trimming, reflection/source-generation compatibility, native publish warnings and AOT readiness scans. Container authoring belongs to containers-images; platform upgrades to dotnet-upgrade.'
---

# .NET Native AOT

Native AOT is an explicitly selected deployment mode, not a mandatory consequence of a framework
upgrade. Keep managed .NET available for workloads whose dependencies or features are incompatible.
Support both .NET 10 and 11; verify the selected release and dependency versions on every use.

## Authorities and Safety

- [Upgrade](../dotnet-upgrade/SKILL.md) owns runtime/language migration and release verification.
- [Container images](../containers-images/SKILL.md) owns toolchains, bases, templates and image audits.
- [Web API](../dotnet-webapi/SKILL.md) owns HTTP contracts; its controller default has an explicit
  Native AOT exception, not permission to migrate every service.
- [EF Core](../dotnet-efcore/SKILL.md) and [gRPC](../dotnet-grpc/SKILL.md) own their provider and
  transport contracts. ASP.NET gRPC support does not prove a code-first serializer is compatible.
- Ask before builds, tests, native publishing, benchmarks and container builds. A readiness scan
  reads local files only; it does not restore packages, invoke a compiler or contact services.
- Do not install SDKs/toolchains, publish packages/images, deploy, commit or push without approval.

## 1. Assess the Actual Workload

Inventory entrypoints, roles, TFMs, RID/OS/CPU targets, native libraries, framework references,
serializers, configuration, DI discovery, HTTP/authentication, data access and plugin mechanisms.
Trace the Release package graph as well as local Debug references. For libraries, assess all
retained TFMs; do not set `PublishAot` on a class library.

Run the bundled heuristic scanner against explicitly selected repositories:

```powershell
./scripts/Find-AotRisks.ps1 -Path <repository> -Format Json
```

Use the [scanner contract and compatibility checklist](references/readiness.md) to interpret
findings. A clean scan is **not proof of AOT compatibility**: patterns cannot evaluate MSBuild,
conditional compilation, runtime types, native dependencies or transitive package behavior.
Reflection is not categorically forbidden; statically discoverable, correctly annotated reflection
can work. Runtime code generation and unbounded dynamic loading need a different design.

Produce a decision table per workload: managed or AOT candidate, evidence, dependency/version
constraints, source changes, target platforms, contract risk and validation still required.
Prefer a small CLI or worker as the first pilot, not an MVC/Blazor host or a reflection-heavy hub.

## 2. Agree the Compatibility Changes

- MVC controllers are not an AOT route. An approved AOT HTTP service uses supported Minimal APIs
  and request-delegate generation; otherwise retain the managed host. Preserve route names,
  authorization, validation, Problem Details, streaming and OpenAPI contracts explicitly.
- Verify authentication schemes, SignalR, Blazor, middleware and hosting features against the
  documentation for the exact ASP.NET version. `CreateSlimBuilder` is an option, not a drop-in
  behavioral equivalent to `CreateBuilder`.
- Use System.Text.Json generated contexts/type metadata covering actual root types, collections,
  polymorphic subtypes and converters; use AOT-compatible enum converters. Check configuration
  binding and options-validation generators independently of JSON generation.
- Prefer explicit registrations or proven source generators over assembly scanning and runtime
  proxy generation. Check the concrete serializer/DI/mapper/RPC package version, not its category.
- Verify EF provider support and any compiled-model/precompiled-query requirements. Experimental
  EF AOT support or a provider without support blocks a production AOT claim; do not rewrite
  persistence or enable experimental tooling implicitly.
- Use annotations only when their data-flow contract is true. Do not blanket-suppress IL2xxx or
  IL3xxx diagnostics, or add linker roots to conceal an unbounded reflection design.

## 3. Publish Deliberately

Set `PublishAot` in the selected executable's project/publish configuration, not as an unconditional
repository-wide property. Set `IsAotCompatible` on a library only after its analyzers and consumer
publish checks justify that promise. Preserve normal managed development and test workflows.

With approval, restore/publish the actual executable in Release for each selected RID, using the
same TFM, AOT, self-contained, feature-switch and dependency settings for both operations.
Investigate every trimming and AOT warning, including dependency warnings and unsupported APIs;
a normal build or `IsAotCompatible` property alone is not the gate.

For the initial Linux container rollout, use `linux/amd64` and `linux/arm64` AOT artifacts built
on matching native builders. Keep managed images for other required platforms. This is a rollout
choice, not a claim that Native AOT universally lacks other architecture support.
Cross-architecture compilation requires the documented linker/toolchain/sysroot; RID selection
alone is insufficient. Cross-OS compilation is not supported. Match libc and build on a distribution
no newer than the deployment base. Delegate exact image inputs to the container skill.

## 4. Prove the Result

- Publish every selected RID and inspect diagnostics from the complete application closure.
- Smoke-run native artifacts on each actual target architecture and runtime base, including
  non-root/read-only execution, health/readiness and graceful cancellation/shutdown.
- Exercise serialization, configuration, auth, endpoints, persistence, RPC and native-library paths
  actually used in production; development-mode managed tests cannot prove the published binary.
- Compare managed and AOT on identical hardware/configuration: cold startup to readiness, steady
  RSS, image/artifact size, representative throughput/latency and build time. Do not promise faster
  throughput or lower memory without measurements; retain the managed path on regression.
- Report `candidate`, `blocked` or `validated for <TFM/RID/workload>` with exact checks and gaps.
  Never report fleet-wide readiness from a regex scan or one successful architecture.

## Maintaining This Skill

- Recheck Native AOT target matrices, Linux toolchains, cross-compilation and diagnostic guidance
  for each supported .NET release.
- Recheck ASP.NET feature support, EF/provider maturity and source-generator coverage independently.
- Extend scanner rules and synthetic tests together; keep findings heuristic and never print
  matched source lines or configuration values.
- Keep managed/AOT template selection and platform policy aligned with the container skill.
