defmodule Wasmex.Test.Support.Examples.CompleteComponentWithResources do
  @moduledoc """
  Example showing how ComponentServer and ResourceComponent work together.

  This demonstrates a complete setup where:
  1. ComponentServer handles regular WASM functions
  2. ResourceComponent handles resource methods with automatic wrapper generation
  3. Both integrate seamlessly with the same WIT file

  ## Example WIT file structure:

  ```wit
  package example:app;

  interface types {
    resource database {
      constructor(url: string);
      query: func(sql: string) -> list<record>;
      close: func();
    }
    
    resource cache {
      get: func(key: string) -> option<string>;
      set: func(key: string, value: string);
      delete: func(key: string);
    }
  }

  world app {
    import types;
    
    export process-data: func(db: borrow<database>) -> string;
    export get-cached: func(cache: borrow<cache>, key: string) -> option<string>;
  }
  ```
  """

  # The main component using ComponentServer for exported functions
  # NOTE: This is a documentation example - paths would be real in production
  if false do
    defmodule AppComponent do
      use Wasmex.Components.ComponentServer,
        wit: "path/to/app.wit",
        imports: %{
          # Resources are provided through ResourceManager
          "types" => :resources
        }
    end
  end

  # Database resource with automatic method generation
  defmodule DatabaseResource do
    use Wasmex.Components.ResourceComponent,
      resource: "database"

    defstruct [:conn, :url, :query_count]

    def init(url) do
      # In a real implementation, you'd connect to the database
      {:ok, %__MODULE__{url: url, conn: :mock_connection, query_count: 0}}
    end

    def handle_method("query", [_sql], state) do
      # Mock query execution
      result = [
        %{id: 1, name: "Alice"},
        %{id: 2, name: "Bob"}
      ]

      new_state = %{state | query_count: state.query_count + 1}
      {:reply, result, new_state}
    end

    def handle_method("close", [], state) do
      # Clean up connection
      {:noreply, %{state | conn: nil}}
    end
    
    def handle_method(method, _params, state) do
      {:error, "Unknown method: #{method}", state}
    end

  end

  # Cache resource with automatic method generation
  defmodule CacheResource do
    use Wasmex.Components.ResourceComponent,
      resource: "cache"

    defstruct data: %{}

    def init(_args) do
      {:ok, %__MODULE__{}}
    end

    def handle_method("get", [key], state) do
      value = Map.get(state.data, key)
      {:reply, value, state}
    end

    def handle_method("set", [key, value], state) do
      new_state = %{state | data: Map.put(state.data, key, value)}
      {:noreply, new_state}
    end

    def handle_method("delete", [key], state) do
      new_state = %{state | data: Map.delete(state.data, key)}
      {:noreply, new_state}
    end
    
    def handle_method(method, _params, state) do
      {:error, "Unknown method: #{method}", state}
    end
  end

  @doc """
  Complete usage example showing ComponentServer and ResourceComponent together.
  """
  def example_usage do
    # NOTE: In a real application, AppComponent would be defined with a real WIT file
    # Start the WASM component
    # {:ok, component_pid} = AppComponent.start_link(wasm: "path/to/app.wasm")

    # Create a store for resources
    # {:ok, store} = Wasmex.Components.Store.new()

    # Create resources that can be passed to WASM
    # {:ok, db_handle} = DatabaseResource.create_for_wasm(store, "postgres://localhost/mydb")
    # {:ok, cache_handle} = CacheResource.create_for_wasm(store, nil)

    # Call WASM functions that use the resources
    # The WASM component can call methods on our Elixir resources
    # result = AppComponent.process_data(component_pid, db_handle)

    # Or use resources standalone with generated wrappers
    {:ok, db_pid} = DatabaseResource.start_link("postgres://localhost/mydb")
    {:ok, cache_pid} = CacheResource.start_link(nil)

    # Use the method wrappers (would be auto-generated with WIT file)
    # records = DatabaseResource.query(db_pid, "SELECT * FROM users")
    # CacheResource.set(cache_pid, "user:1", Jason.encode!(records))
    # cached = CacheResource.get(cache_pid, "user:1")

    # Clean up
    # DatabaseResource.close(db_pid)
    DatabaseResource.stop(db_pid)
    CacheResource.stop(cache_pid)

    :ok
  end

  @doc """
  Example showing supervision tree integration.
  """
  def supervision_example do
    children = [
      # WASM component server (would be used with real WIT file)
      # {AppComponent, wasm: "path/to/app.wasm"},

      # Resource servers (can be supervised independently)
      {DatabaseResource, "postgres://localhost/mydb"},
      {CacheResource, nil},

      # Dynamic supervisor for on-demand resources
      {DynamicSupervisor, name: MyApp.ResourceSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
