---
name: dotnet-polymorphic-configuration
description: 'Design, implement, audit or troubleshoot polymorphic .NET configuration using System.Text.Json discriminators. Use for heterogeneous interface/base-class DTO arrays, $type, JsonPolymorphic, JsonDerivedType, IConfiguration-to-JsonNode bridges, IAppConfig-style loaders, options registration and recursive startup validation. Not arbitrary CLR type loading or runtime strategy execution.'
argument-hint: '[design|apply|audit|diagnose] [configuration section or options type]'
user-invocable: true
---

# .NET Polymorphic Configuration

Bind a configuration graph containing different DTO implementations without losing configuration
provider precedence or assuming the standard binder understands JSON polymorphism.

## Authorities and Scope

- Follow the [configuration instructions](../../instructions/dotnet.configuration.instructions.md)
  for provider ordering, defaults, startup validation and snapshot/reload policy, and the
  [C# instructions](../../instructions/dotnet.csharp.instructions.md) for implementation conventions.
- System.Text.Json owns discriminator-based deserialization. The standard
  `Microsoft.Extensions.Configuration` binder does not honour `[JsonPolymorphic]`,
  `[JsonDerivedType]` or JSON converters when binding an interface-typed property.
- An application marker such as `IAppConfig` may select the section and registration path; it does
  not enable polymorphism. Keep DTO selection separate from constructing executable services.
- Use the official [polymorphism guide](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/polymorphism)
  and [options guide](https://learn.microsoft.com/en-us/dotnet/core/extensions/options) when checking
  framework-specific behaviour.

## Workflow

1. Establish mode: `audit` and `diagnose` are read-only; `design` proposes a contract; `apply`
   implements the requested binding path and its consumers.
2. Trace the root options type, nested interface/abstract properties, derived DTOs, section name,
   providers, options scans, validators and consumers. Search for a shared JSON bridge before
   adding another. Determine which properties genuinely require heterogeneous types.
3. Define a finite discriminator map on each interface/base class. Use stable domain-neutral
   string identifiers, not assembly-qualified CLR names. Reject unknown discriminators; do not
   fall back to another DTO or resolve arbitrary types with `Type.GetType`.
4. Choose how to reconstruct the merged configuration subtree using the bridge contract below.
   Do not deserialize only the base settings file and thereby bypass environment variables,
   secrets providers, command-line overrides or other configured providers.
5. Deserialize using explicitly configured System.Text.Json options. Match the application's
   property-name, enum, number, date and converter contracts; do not assume configuration-binder
   conversion rules are identical to serializer rules.
6. Validate the complete relevant graph, including concrete derived DTOs, then register it once.
   Preserve application-specific activation rules rather than assuming inactive entries are valid
   or that every inactive template must be fully populated.
7. Update affected configuration examples, registrations and consumers together. Consider extracting
   a reusable bridge into an existing shared configuration library when there are real consumers;
   keep application-specific discriminator maps and activation policy local.

## Discriminator Contract

This illustrative contract uses System.Text.Json polymorphism available from .NET 7 onward.
Use the consuming repository's supported target framework and C# conventions.

```csharp
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

[JsonPolymorphic(TypeDiscriminatorPropertyName = "$type")]
[JsonDerivedType(typeof(IntervalTaskConfig), "interval")]
[JsonDerivedType(typeof(BatchTaskConfig), "batch")]
public interface ITaskConfig;

public sealed record IntervalTaskConfig : ITaskConfig
{
    [Range(1, 86400)]
    public int IntervalSeconds { get; init; } = 60;
}

public sealed record BatchTaskConfig : ITaskConfig
{
    [Range(1, 1000)]
    public int BatchSize { get; init; } = 100;
}

public sealed record ProcessingConfig
{
    public ITaskConfig[] Tasks { get; init; } = [];
}
```

The corresponding configuration section fragment is:

```json
{
  "Processing": {
    "Tasks": [
      { "$type": "interval", "IntervalSeconds": 30 },
      { "$type": "batch", "BatchSize": 50 }
    ]
  }
}
```

Each array element deserializes to its declared concrete DTO. A separate strategy family needs its
own interface/base contract and discriminator map. A discriminator names the DTO shape, not a DI
registration. Treat changes to discriminator names or derived properties as configuration-contract
changes.

## Configuration-to-JSON Bridge

The binding flow is:

```text
merged IConfiguration section
  -> reconstructed JsonObject / JsonArray / JsonValue
  -> JsonSerializer deserialization to the root DTO
  -> graph validation
  -> options registration
```

Implement or reuse a recursive section-to-`JsonNode` conversion with an explicit shape contract:

- Enumerate `GetChildren()` from the merged section. Do not serialize `IConfiguration` itself.
  Configuration flattens JSON into hierarchical string-valued keys; the original JSON tokens
  are not generally recoverable.
- Distinguish objects, arrays and dictionaries using the target DTO contract or a documented
  restricted shape. An all-numeric key set is ambiguous: it may represent an array or a dictionary.
  If numeric-key inference is used, constrain where it applies, sort numerically with invariant
  parsing and decide how sparse indexes are handled. Do not silently compact them unless that is
  the agreed contract.
- Emit `$type` before ordinary object members. Configuration enumeration does not preserve source
  JSON property order. Newer System.Text.Json versions offer `AllowOutOfOrderMetadataProperties`;
  use it only after checking target support and buffering implications. Ordering metadata first
  avoids requiring that option.
- Preserve discriminator values and string-valued properties exactly. A blanket bool/long/double
  inference can corrupt strings such as `"00123"` or `"true"` and lose decimal precision. Prefer
  target-aware conversion or narrow converters for known scalar types. If retaining an existing
  heuristic bridge, document its restricted input domain and test the actual supported values.
- `JsonNumberHandling.AllowReadingFromString` can support numeric DTO properties from configuration
  strings; it does not convert string booleans. Configure enum conversion explicitly when enum
  names are allowed. Use invariant numeric parsing and avoid a double intermediary for decimals.
- Treat missing sections, explicit null, empty strings, empty objects and empty arrays deliberately.
  Provider/runtime versions may represent them differently; a leaf is not automatically null
  merely because its value is empty. Do not silently turn an invalid required section into a
  default options instance.
- Providers merge individual array index keys, not whole arrays atomically. A shorter override may
  retain earlier indexes. Changing only `$type` can also retain properties of the previous subtype.
  Test both cases; require a deliberate replacement policy where whole-list replacement is needed.
- Fail with the affected configuration path and a safe reason. Do not dump raw JSON, secret-bearing
  values or serializer exception details into logs.

The bridge is not a general lossless JSON round-trip. Where distinctions have already been lost by
providers, constrain the configuration contract or choose a deliberately different representation;
do not invent values to make deserialization succeed.

## Validation and Options Registration

- Deserialization selects concrete types; it does not execute DataAnnotations validation.
  C# `required`/JSON required-member handling is also distinct from semantic `[Required]` or
  `[Range]` validation.
- `Validator.ValidateObject(..., validateAllProperties: true)` validates the current object, not
  its complete nested graph. `ValidateDataAnnotations()` likewise does not recursively validate
  every child. `[ValidateObjectMembers]` and `[ValidateEnumeratedItems]` are consumed by the options
  validation source generator, not automatically by a manual DataAnnotations call.
- Validate nested objects, collection elements and dictionary values explicitly, with paths that
  identify the failing element. Dispatch on the actual derived type so subtype-specific rules
  are enforced. Include `IValidatableObject` cross-property rules. If using generated validators,
  verify concrete subtype coverage rather than assuming interface annotations are sufficient.
- Preserve registered `IValidateOptions<T>` validators. Prefer integrating custom deserialization
  into the existing options pipeline with startup validation. A loader that validates manually
  must invoke all relevant validators explicitly; replacing registration with
  `Options.Create(config)` bypasses normal factory-driven validation.
- A singleton `IOptions<T>` created with `Options.Create` is a startup snapshot. It does not provide
  reload, named options, post-configuration or automatic validator execution. Use it only when that
  is the intended contract and validation has already succeeded.
- Check assembly scans and conventional `.BindConfiguration(...)` calls. Exclude specially bound
  roots from ordinary binding, or route them through one supported loader; registration order
  must not cause the interface graph to be rebound by the standard binder.

## Verification and Reporting

Ask before running tests. With approval, use the consumer's existing test tooling and synthetic,
credential-free configuration. Verify concrete runtime types and property values, not just a
non-null root. Cover:

- Every declared subtype and multiple mixed elements in one array.
- Missing, unknown and incorrectly cased discriminator values according to the agreed contract.
- Provider precedence, metadata ordering, more than ten indexes, sparse indexes and numeric-key
  dictionaries where supported.
- String booleans, enum names, decimal precision, numeric-looking strings, null/empty/missing values
  and defaults using the actual supported providers and runtime.
- Shorter array overlays and subtype changes at the same index, including stale properties.
- Invalid subtype-specific annotations, nested and dictionary paths, cross-property rules,
  activation policy and registered options validators.
- Startup failure for invalid configuration, single registration and the intended snapshot/reload
  behaviour. Include serializer source-generation metadata if trimming/AOT is supported.

Report the discriminator map, binding route, validation coverage, provider/collection limitations,
checks performed and remaining gaps. Do not claim reload support or runtime verification from
source inspection alone; do not commit, publish or deploy as a side effect.

## Maintaining This Skill

- Recheck configuration-provider null/empty and array-overlay behaviour when supported .NET versions change.
- Recheck System.Text.Json metadata ordering, unknown-type behaviour, scalar converters and AOT support.
- Extend synthetic acceptance cases when another consumer reveals a shape or validation boundary.
- Keep generic bridge mechanics here and provider ordering/options policy in the configuration instructions.
