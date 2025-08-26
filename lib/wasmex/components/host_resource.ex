defprotocol Wasmex.Components.HostResource do
  @moduledoc """
  Protocol for implementing host-defined resources that can be passed to WASM components.
  
  Host resources allow Elixir code to define custom resources with methods that can be
  called from within WASM components. This enables powerful patterns like:
  
  - Database connections as resources
  - Message queue handles
  - Custom stateful services
  - File system abstractions
  - Network connections managed by Elixir
  
  ## Implementing the Protocol
  
  To create a host resource, implement this protocol for your struct:
  
      defmodule MyApp.DatabaseConnection do
        defstruct [:conn, :query_count]
        
        defimpl Wasmex.Components.HostResource do
          def type_name(_resource), do: "database-connection"
          
          def call_method(resource, "query", [sql]) do
            result = MyApp.Database.query(resource.conn, sql)
            {:ok, result}
          end
          
          def call_method(resource, "begin-transaction", []) do
            MyApp.Database.begin(resource.conn)
            {:ok, nil}
          end
          
          def call_method(_resource, method, _params) do
            {:error, "Unknown method: \#{method}"}
          end
          
          def drop(resource) do
            MyApp.Database.close(resource.conn)
            :ok
          end
        end
      end
  
  ## Type System
  
  Host resources must declare their type name, which is used by WASM components
  to identify the resource type. The type name should be a valid WIT identifier
  (lowercase with hyphens).
  
  ## Method Dispatch
  
  The `call_method/3` function receives the method name and parameters from the
  WASM component and should return either `{:ok, result}` or `{:error, reason}`.
  
  Parameters and return values are automatically converted between Elixir and WASM types:
  
  - Numbers: integer, float
  - Strings: binary
  - Booleans: true/false
  - Lists: list of supported types
  - Records: map with atom keys
  - Resources: other resource references
  - Options: `{:some, value}` or `:none`
  - Results: `{:ok, value}` or `{:error, value}`
  
  ## Resource Lifecycle
  
  The `drop/1` function is called when the resource is no longer needed. This should
  clean up any associated state, close connections, etc. It's guaranteed to be called
  exactly once per resource instance.
  """
  
  @doc """
  Returns the WIT type name for this resource.
  
  This should be a valid WIT identifier (lowercase with hyphens).
  For example: "database-connection", "message-queue", "file-handle"
  """
  @spec type_name(t) :: String.t()
  def type_name(resource)
  
  @doc """
  Calls a method on the host resource.
  
  This function is invoked when a WASM component calls a method on this resource.
  The method name and parameters are passed from the component.
  
  ## Parameters
  
  - `resource` - The resource struct
  - `method` - The method name as a string
  - `params` - List of parameters from the WASM component
  
  ## Return Values
  
  - `{:ok, result}` - Success with optional return value
  - `{:error, reason}` - Error with reason
  
  The result value will be automatically converted to the appropriate WASM type.
  """
  @spec call_method(t, String.t(), list()) :: {:ok, any()} | {:error, any()}
  def call_method(resource, method, params)
  
  @doc """
  Drops the resource, cleaning up any associated state.
  
  This is called when the resource is no longer needed. It should:
  
  - Close any open connections
  - Release any held resources
  - Clean up any associated state
  
  This function is guaranteed to be called exactly once per resource instance,
  either when explicitly dropped by the WASM component or when the store is destroyed.
  
  ## Return Values
  
  - `:ok` - Resource successfully dropped
  - `{:error, reason}` - Error dropping resource (logged but not propagated to WASM)
  """
  @spec drop(t) :: :ok | {:error, any()}
  def drop(resource)
end