using System.Collections.Concurrent;
using System.Data;
using Microsoft.Data.SqlClient;

namespace MigrationLab;

public static class Program
{
    public static void Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);
        builder.Services.AddProblemDetails();
        if (builder.Environment.IsEnvironment("Testing"))
            builder.Services.AddSingleton<ICatalogStore, MemoryCatalogStore>();
        else
            builder.Services.AddSingleton<ICatalogStore, SqlCatalogStore>();
        builder.Services.AddSingleton<WriteGate>();
        var app = builder.Build();
        app.UseExceptionHandler();
        app.UseDefaultFiles();
        app.UseStaticFiles();
        app.MapGet("/health/live", () => Results.Ok(new { status = "live" }));
        app.MapGet("/health/ready", async (ICatalogStore store, CancellationToken ct) =>
        {
            try { await store.CheckAsync(ct); return Results.Ok(new { status = "ready" }); }
            catch (Exception ex) when (ex is SqlException or InvalidOperationException)
            { return Results.Problem(statusCode: 503, title: "Database is not ready"); }
        });
        app.MapGet("/api/status", (IConfiguration config, ICatalogStore store, WriteGate gate) => Results.Ok(new
        {
            site = config["Lab:Site"] ?? "source", readOnly = gate.IsReadOnly,
            store = store is MemoryCatalogStore ? "test-memory" : "sql"
        }));
        app.MapGet("/api/catalog", async (ICatalogStore store, CancellationToken ct) =>
            Results.Ok(await store.ReadAsync(ct)));
        app.MapPost("/api/catalog", async (CatalogInput input, ICatalogStore store, WriteGate gate, CancellationToken ct) =>
        {
            // Serialize writes and recheck the marker after taking the gate. Migration also
            // makes SQL READ_ONLY, which is the durable boundary for in-flight requests.
            if (string.IsNullOrWhiteSpace(input.Name) || input.Name.Trim().Length > 100 || input.Quantity < 0 || input.Quantity > 1000000)
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["catalog"] = ["Name must contain 1–100 characters; quantity must be 0–1000000."] });
            await gate.Mutex.WaitAsync(ct);
            try
            {
                if (gate.IsReadOnly)
                    return Results.Problem(statusCode: 423, title: "Migration acceptance is read-only");
                var item = await store.AddAsync(input with { Name = input.Name.Trim() }, ct);
                return Results.Created($"/api/catalog/{item.Id}", item);
            }
            finally { gate.Mutex.Release(); }
        });
        app.Run();
    }
}

public record CatalogItem(int Id, string Name, int Quantity);
public record CatalogInput(string Name, int Quantity);

public sealed class WriteGate(IConfiguration config)
{
    public SemaphoreSlim Mutex { get; } = new(1, 1);
    public bool IsReadOnly => File.Exists(config["Lab:ReadOnlyMarker"] ?? @"C:\MigrationLab\readonly.flag");
}

public interface ICatalogStore
{
    Task CheckAsync(CancellationToken ct);
    Task<IReadOnlyList<CatalogItem>> ReadAsync(CancellationToken ct);
    Task<CatalogItem> AddAsync(CatalogInput item, CancellationToken ct);
}

public sealed class SqlCatalogStore(IConfiguration config) : ICatalogStore
{
    private SqlConnection Connection() => new(config.GetConnectionString("Lab")
        ?? throw new InvalidOperationException("ConnectionStrings:Lab is required outside the Testing environment."));
    public async Task CheckAsync(CancellationToken ct)
    {
        await using var db = Connection();
        await db.OpenAsync(ct);
        await using var cmd = new SqlCommand("SELECT TOP (1) Id FROM dbo.Catalog", db);
        await cmd.ExecuteScalarAsync(ct);
    }
    public async Task<IReadOnlyList<CatalogItem>> ReadAsync(CancellationToken ct)
    {
        await using var db = Connection();
        await db.OpenAsync(ct);
        await using var cmd = new SqlCommand("SELECT Id, Name, Quantity FROM dbo.Catalog ORDER BY Id", db);
        await using var rows = await cmd.ExecuteReaderAsync(ct);
        var items = new List<CatalogItem>();
        while (await rows.ReadAsync(ct)) items.Add(new(rows.GetInt32(0), rows.GetString(1), rows.GetInt32(2)));
        return items;
    }
    public async Task<CatalogItem> AddAsync(CatalogInput item, CancellationToken ct)
    {
        await using var db = Connection();
        await db.OpenAsync(ct);
        await using var cmd = new SqlCommand("INSERT dbo.Catalog(Name,Quantity) OUTPUT inserted.Id VALUES(@name,@quantity)", db);
        cmd.Parameters.Add("@name", SqlDbType.NVarChar, 100).Value = item.Name;
        cmd.Parameters.Add("@quantity", SqlDbType.Int).Value = item.Quantity;
        var id = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct));
        return new(id, item.Name, item.Quantity);
    }
}

// This implementation is registered only by the explicit Testing host environment.
public sealed class MemoryCatalogStore : ICatalogStore
{
    private readonly ConcurrentDictionary<int, CatalogItem> items = new();
    private int nextId;
    public Task CheckAsync(CancellationToken ct) => Task.CompletedTask;
    public Task<IReadOnlyList<CatalogItem>> ReadAsync(CancellationToken ct) =>
        Task.FromResult<IReadOnlyList<CatalogItem>>(items.Values.OrderBy(x => x.Id).ToList());
    public Task<CatalogItem> AddAsync(CatalogInput item, CancellationToken ct)
    {
        var result = new CatalogItem(Interlocked.Increment(ref nextId), item.Name, item.Quantity);
        items[result.Id] = result;
        return Task.FromResult(result);
    }
}
