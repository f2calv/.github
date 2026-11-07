using Example.Minimal.SampleApp;
using Example.Widgets.Services;

var builder = WebApplication.CreateSlimBuilder(args);
builder.Logging.ClearProviders();
var widgetsEnabled = !args.Contains("--disable-widgets", StringComparer.Ordinal);
if (widgetsEnabled)
{
    builder.Services.AddSingleton<WidgetService>();
}
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonSerializerContext.Default));
var app = builder.Build();
if (widgetsEnabled)
{
    WidgetEndpoints.Map(app);
}
await app.StartAsync();
Console.WriteLine(app.Urls.Single());
await app.WaitForShutdownAsync();
