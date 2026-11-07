using Example.Widgets.Models;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json.Serialization;

namespace Example.Minimal.SampleApp;

/// <summary>Generated JSON metadata for the fixture's response bodies.</summary>
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(CreateWidgetRequest))]
[JsonSerializable(typeof(ProblemDetails))]
[JsonSerializable(typeof(HttpValidationProblemDetails))]
[JsonSerializable(typeof(WidgetResponse))]
internal partial class AppJsonSerializerContext : JsonSerializerContext;
