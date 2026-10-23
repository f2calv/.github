# Cached Read With Invalidation on Write

A synthetic catalog service that reads products through `IDistributedCache`, expires entries with
absolute jitter, and invalidates on write. It shows the shape only; the product store stands in for
the application's authoritative database or API. Target .NET 8 or later.

## Key and Role

| Key | Role | Type | Expiry | Writer | Readers |
| --- | --- | --- | --- | --- | --- |
| `catalog:cache:product:{id}` | Cache | String | Absolute, 10 minutes plus up to 10% jitter | Cache-aside loader | `ProductCatalogService` |

## `Models/CatalogConfig.cs`

```csharp
using System.ComponentModel.DataAnnotations;

namespace Example.Models;

public sealed record CatalogConfig
{
    public const string ConfigurationSectionName = "Example:CatalogConfig";

    /// <summary>Base lifetime of a cached product in milliseconds.</summary>
    /// <remarks>Used by <see cref="Example.Services.ProductCatalogService"/>.</remarks>
    [Range(1, int.MaxValue)]
    public int ProductCacheTtlMs { get; init; } = 600_000;
}
```

## `Services/ProductCatalogService.cs`

```csharp
using CasCap.Common.Abstractions;
using Example.Abstractions;
using Example.Models;
using Microsoft.Extensions.Options;

namespace Example.Services;

public sealed class ProductCatalogService(IOptions<CatalogConfig> config, TimeProvider timeProvider,
    IDistributedCache distributedCache, IProductStore productStore)
{
    private const double JitterRatio = 0.1;

    public Task<Product?> GetProductAsync(string productId, CancellationToken cancellationToken)
        => distributedCache.Get(ProductKey(productId),
            () => productStore.GetAsync(productId, cancellationToken),
            absoluteExpiration: ProductExpiry());

    public async Task UpdateProductAsync(Product product, CancellationToken cancellationToken)
    {
        //Change the authority first, then delete the cached copy so the next read loads the committed value.
        await productStore.UpdateAsync(product, cancellationToken).ConfigureAwait(false);
        await distributedCache.Delete(ProductKey(product.Id)).ConfigureAwait(false);
    }

    private static string ProductKey(string productId) => $"catalog:cache:product:{productId}";

    private DateTimeOffset ProductExpiry()
    {
        var ttl = TimeSpan.FromMilliseconds(config.Value.ProductCacheTtlMs);
        var jitter = TimeSpan.FromMilliseconds(ttl.TotalMilliseconds * JitterRatio * Random.Shared.NextDouble());
        return timeProvider.GetUtcNow() + ttl + jitter;
    }
}
```

`IProductStore.GetAsync` returns `Task<Product>` and throws when the product does not exist. A
store that returns `null` for a missing product is fetched on every call, because the cache does
not store `null`; cache an explicit empty value with a short expiry if that is frequent.

`Product` is a plain record. With `RemoteCache.SerializationType` set to `MessagePack` (the
library default), annotate it for MessagePack; the configuration below uses JSON instead.

## Registration

```csharp
_ = builder.Services.AddCasCapCaching(builder.Configuration);
builder.Services.AddOptionsWithValidateOnStart<CatalogConfig>()
    .BindConfiguration(CatalogConfig.ConfigurationSectionName)
    .ValidateDataAnnotations();
builder.Services.AddSingleton<IProductStore, ProductStore>();
builder.Services.AddSingleton<ProductCatalogService>();
```

`AddCasCapCaching` registers `TimeProvider.System` on .NET 8 or later when none is registered.

## `appsettings.json`

```json
{
  "CasCap": {
    "CachingConfig": {
      "RemoteCacheConnectionString": "redis.example.com:6379,abortConnect=false",
      "DistributedLockingEnabled": true,
      "RemoteCache": {
        "SerializationType": "Json"
      }
    }
  }
}
```

`Example:CatalogConfig` is omitted because the code default applies. Enable
`DistributedLockingEnabled` only when the product store is slow, rate limited or charged per call.

## Tests to Add

- Two concurrent `GetProductAsync` calls for one identifier call the store once.
- `UpdateProductAsync` calls the store before deleting the key, and a following read reloads.
- The computed expiry lies between the base TTL and the base TTL plus 10%, using `FakeTimeProvider`.
