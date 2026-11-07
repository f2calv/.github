using Example.Widgets.Services;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
var widgetsEnabled = !args.Contains("--disable-widgets", StringComparer.Ordinal);
if (widgetsEnabled)
{
    builder.Services.AddSingleton<WidgetService>();
    builder.Services.AddControllers();
}
var app = builder.Build();
if (widgetsEnabled)
{
    app.MapControllers();
}
await app.StartAsync();
Console.WriteLine(app.Urls.Single());
await app.WaitForShutdownAsync();
