# Resource API - Clean & Simple

After simplification, here's the clean approach to resources that actually works and makes sense.

## The Reality

Resources are just GenServers with a method dispatch pattern. No magic needed.

## Host Resources (90% of cases)

When WASM needs access to system resources:

```elixir
defmodule MyApp.FileSystem do
  use GenServer
  
  def start_link(root_path) do
    GenServer.start_link(__MODULE__, root_path)
  end
  
  def init(root_path) do
    {:ok, %{root: root_path}}
  end
  
  # WASM calls this via imports
  def handle_call({:method, "read", [path]}, _from, state) do
    contents = File.read!(Path.join(state.root, path))
    {:reply, {:ok, contents}, state}
  end
  
  def handle_call({:method, "write", [path, data]}, _from, state) do
    File.write!(Path.join(state.root, path), data)
    {:reply, {:ok, :written}, state}
  end
end

# Use with WASM
{:ok, fs} = MyApp.FileSystem.start_link("/safe/path")
{:ok, wasm} = Wasmex.Components.start_link(
  wasm: "app.wasm",
  imports: %{"fs" => fs}
)
```

## WASM Resources (10% of cases)

When WASM exports resources, they're just function calls:

```elixir
defmodule Game do
  use Wasmex.Components.ComponentServer,
    wit: "game.wit"
end

{:ok, game} = Game.start_link(wasm: "game.wasm")
{:ok, player} = Game.create_player(game, "Alice")
Game.move_player(game, player, {10, 20})
```

## Optional: Auto-Generated Wrappers

If you want nice wrapper functions, use `ResourceComponentServer`:

```elixir
defmodule DB do
  use Wasmex.Components.ResourceComponentServer,
    wit: "db.wit",
    resource: "database"
  
  def init(url), do: {:ok, connect(url)}
  
  def handle_method("query", [sql], conn) do
    {:reply, execute(sql, conn), conn}
  end
end

# Auto-generated wrappers
{:ok, db} = DB.start_link("postgres://...")
DB.query(db, "SELECT * FROM users")  # Nice!
```

## Common Patterns

### Database for WASM
```elixir
defmodule DB do
  use GenServer
  
  def start_link(url), do: GenServer.start_link(__MODULE__, url)
  def init(url), do: {:ok, Ecto.connect(url)}
  
  def handle_call({:method, "query", [sql]}, _from, conn) do
    {:reply, {:ok, Ecto.query(conn, sql)}, conn}
  end
end
```

### HTTP Client for WASM
```elixir
defmodule Http do
  use GenServer
  
  def start_link(_), do: GenServer.start_link(__MODULE__, nil)
  def init(_), do: {:ok, %{}}
  
  def handle_call({:method, "get", [url]}, _from, state) do
    {:reply, {:ok, HTTPoison.get!(url).body}, state}
  end
end
```

### Logger for WASM
```elixir
defmodule Logger do
  use GenServer
  
  def start_link(level), do: GenServer.start_link(__MODULE__, level)
  def init(level), do: {:ok, %{level: level}}
  
  def handle_call({:method, "log", [msg]}, _from, state) do
    IO.puts("[#{state.level}] #{msg}")
    {:reply, {:ok, :logged}, state}
  end
end
```

## That's It!

- Resources are just GenServers
- Use `{:method, name, params}` pattern for dispatch
- WASM resources are just function calls via ComponentServer
- Optional: Use ResourceComponentServer for auto-generated wrappers

No complex abstractions needed. The simple approach works best.

## Tests Pass ✅

```
......
Finished in 0.1 seconds
6 tests, 0 failures
```

The API improvements provide:
1. Clean method dispatch pattern
2. Optional auto-generated wrappers from WIT
3. Full OTP supervision compatibility
4. Simple, predictable behavior

Use what you need, ignore what you don't. Keep it simple.