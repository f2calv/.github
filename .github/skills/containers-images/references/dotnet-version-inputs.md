# .NET Version Inputs

All managed, Debug and AOT templates share `SDK_TAG`, `TARGET_FRAMEWORK` and `RUNTIME_TAG`.
They are literal authoring substitutions, not a version resolver. Choose the deployment model first;
then resolve the complete bundle before rendering. Keep `global.json` compatible with the selected
SDK and the project's target framework.

## Stable Bundle and Release Gate

The [.NET 10 substitution table](../examples/dotnet-service.md#resolve-inputs) is the stable baseline.
The [official SDK tag listing](https://github.com/dotnet/dotnet-docker/blob/main/README.sdk.md) and
[runtime-deps listing](https://github.com/dotnet/dotnet-docker/blob/main/README.runtime-deps.md)
confirm Noble and Noble AOT SDK tags and the Noble chiseled-extra runtime-deps variant.

For .NET 11, require all of these before replacing the bundle:

1. Verify GA from the [.NET release index](https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json)
   and version-specific release metadata; preview/RC and an unqualified major tag are not GA proof.
2. Read the actual SDK, aspnet/runtime or runtime-deps tag listing for the chosen version and OS.
   Never assume Noble remains the default or derive an AOT tag by appending a suffix.
3. Inspect each selected registry manifest for every declared platform, including the AOT SDK.
   An SDK's managed platform matrix does not imply the AOT toolchain has the same matrix.
4. Align SDK/TFM/runtime, distribution age, glibc versus musl and native libraries. Then render the
   existing templates, audit them and, with approval, build/smoke-test on each native target.

Until that evidence exists, keep .NET 10 inputs; there is deliberately no concrete .NET 11 bundle
here. A tag listing can contain moving aliases pointing to prerelease images.

## Native Toolchain and Culture

Prefer the official version-selected SDK `-aot` variant. If unavailable, use the matching Ubuntu
SDK and install `clang` and `zlib1g-dev` **only in build**, in one update/install/cleanup heredoc:

```dockerfile
RUN <<EOF
set -eux
apt-get update
apt-get install -y --no-install-recommends clang zlib1g-dev
rm -rf /var/lib/apt/lists/*
EOF
```

Keep the compiler, linker and development packages out of runtime-deps. The stable AOT bundle
chooses `INVARIANT_GLOBALIZATION=false` and `noble-chiseled-extra` deliberately for ICU/time zones.
For invariant applications, select only a verified runtime-deps variant with the native libraries
the output needs; do not invent a `chiseled-aot` tag. Alpine requires a matching musl toolchain/RID
and runtime, not a glibc binary copied into Alpine.

Application trimming, reflection, serializers and dependency suitability belong to
[dotnet-aot](../../dotnet-aot/SKILL.md), not the Dockerfile audit.
