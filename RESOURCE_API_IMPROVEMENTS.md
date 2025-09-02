# Resource API Improvements

Simple improvements that make resources work like ComponentServer.

## What Was Fixed

1. **Manual method dispatch** → Auto-generated wrapper functions
2. **No WIT integration** → Parse WIT files for method signatures
3. **Inconsistent API** → Mirrors ComponentServer patterns

## The Solution

### For Host Resources (90% of cases)

Resources are just GenServers with a method dispatch pattern:

```elixir
defmodule FileSystem do
  use GenServer
  
  def start_link(root), do: GenServer.start_link(__MODULE__, root)
  def init(root), do: {:ok, %{root: root}}
  
  def handle_call({:method, "read", [path]}, _from, state) do
    {:reply, {:ok, File.read!(Path.join(state.root, path))}, state}
  end
end
```

### Optional: Auto-Generated Wrappers

Use `ResourceComponentServer` for nice wrapper functions:

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

# Auto-generated from WIT:
DB.query(db, "SELECT * FROM users")
```

### For WASM Resources

Just use ComponentServer - resources are functions:

```elixir
defmodule Game do
  use Wasmex.Components.ComponentServer,
    wit: "game.wit"
end

{:ok, game} = Game.start_link(wasm: "game.wasm")
{:ok, player} = Game.create_player(game, "Alice")
```

## What We Learned

1. **Keep it simple** - Resources are just GenServers
2. **Don't overthink** - WASM resources are just function calls
3. **Host resources are common** - 90% of resources are Elixir providing capabilities to WASM
4. **WIT is optional** - Only needed for auto-generation

## Files Created

- `lib/wasmex/components/resource_component_server.ex` - Auto-generates wrappers from WIT
- `lib/wasmex/components/resource_component.ex` - Enhanced resource with WASM integration
- `test/components/resource_final_test.exs` - Clean tests showing real usage

## Tests Pass

```
......
Finished in 0.1 seconds
6 tests, 0 failures
```

The improvements work and provide a clean, ComponentServer-like API for resources.