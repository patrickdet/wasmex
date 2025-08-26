defmodule Wasmex.Components.HostResourceManager do
  @moduledoc """
  Manages host-defined resources and their interaction with WASM components.
  
  This module provides the bridge between Elixir-defined resources (via the
  `Wasmex.Components.HostResource` protocol) and WASM components that consume them.
  
  ## Usage
  
      # Define a resource that implements the protocol
      resource = %MyApp.DatabaseConnection{conn: db_conn}
      
      # Create a host resource handle
      {:ok, handle} = Wasmex.Components.HostResourceManager.create(store, resource)
      
      # Pass the handle to a WASM function
      Wasmex.Components.Instance.call_function(instance, "process-data", [handle], from)
  
  ## Resource Registry
  
  Host resources are registered per-store and are automatically cleaned up when
  the store is destroyed. Each resource is assigned a unique ID that allows
  the Rust side to dispatch method calls back to Elixir.
  """
  
  use GenServer
  require Logger
  
  @type resource_id :: pos_integer()
  @type resource_handle :: reference()
  
  # Client API
  
  @doc """
  Starts the host resource manager.
  
  This is typically started as part of the application supervision tree.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Creates a new host resource handle that can be passed to WASM components.
  
  ## Parameters
  
  - `store` - The component store
  - `resource` - An Elixir struct that implements `Wasmex.Components.HostResource`
  
  ## Returns
  
  - `{:ok, handle}` - A resource handle that can be passed to WASM
  - `{:error, reason}` - If resource creation fails
  """
  @spec create(Wasmex.Components.Store.t(), any()) :: 
    {:ok, resource_handle()} | {:error, any()}
  def create(store, resource) do
    GenServer.call(__MODULE__, {:create, store, resource})
  end
  
  @doc """
  Calls a method on a host resource.
  
  This is invoked by the Rust NIF when a WASM component calls a method
  on a host-defined resource.
  
  ## Parameters
  
  - `resource_id` - The unique ID of the resource
  - `method` - The method name
  - `params` - List of parameters
  
  ## Returns
  
  - `{:ok, result}` - Success with result
  - `{:error, reason}` - If method call fails
  """
  @spec call_method(resource_id(), String.t(), list()) :: 
    {:ok, any()} | {:error, any()}
  def call_method(resource_id, method, params) do
    GenServer.call(__MODULE__, {:call_method, resource_id, method, params})
  end
  
  @doc """
  Drops a host resource.
  
  This is called when the resource is explicitly dropped by WASM or
  when the store is being cleaned up.
  
  ## Parameters
  
  - `resource_id` - The unique ID of the resource
  
  ## Returns
  
  - `:ok` - Resource successfully dropped
  - `{:error, reason}` - If drop fails
  """
  @spec drop(resource_id()) :: :ok | {:error, any()}
  def drop(resource_id) do
    GenServer.call(__MODULE__, {:drop, resource_id})
  end
  
  @doc """
  Drops all resources associated with a store.
  
  This is called when a store is being destroyed to ensure all
  host resources are properly cleaned up.
  
  ## Parameters
  
  - `store_id` - The store ID
  
  ## Returns
  
  - `:ok` - All resources dropped
  """
  @spec drop_store_resources(pos_integer()) :: :ok
  def drop_store_resources(store_id) do
    GenServer.call(__MODULE__, {:drop_store_resources, store_id})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # State structure:
    # - resources: Map of resource_id -> {resource, store_id}
    # - next_id: Next available resource ID
    # - store_resources: Map of store_id -> Set of resource_ids
    state = %{
      resources: %{},
      next_id: 1,
      store_resources: %{}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:create, store, resource}, _from, state) do
    # Validate that the resource implements the protocol
    if not Wasmex.Components.HostResource.impl_for(resource) do
      {:reply, {:error, "Resource does not implement HostResource protocol"}, state}
    else
      # Get the store ID from the store reference
      store_id = get_store_id(store)
      
      # Allocate a new resource ID
      resource_id = state.next_id
      
      # Get the resource type name
      type_name = Wasmex.Components.HostResource.type_name(resource)
      
      # Create the native resource handle via NIF
      case Wasmex.Native.host_resource_new(store, resource_id, type_name) do
        {:ok, handle} ->
          # Store the resource mapping
          resources = Map.put(state.resources, resource_id, {resource, store_id})
          
          # Track resources by store
          store_resources = 
            Map.update(state.store_resources, store_id, MapSet.new([resource_id]), fn set ->
              MapSet.put(set, resource_id)
            end)
          
          new_state = %{
            state | 
            resources: resources,
            next_id: resource_id + 1,
            store_resources: store_resources
          }
          
          Logger.debug("Created host resource #{resource_id} of type #{type_name} for store #{store_id}")
          
          {:reply, {:ok, handle}, new_state}
          
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end
  
  @impl true
  def handle_call({:call_method, resource_id, method, params}, _from, state) do
    case Map.get(state.resources, resource_id) do
      {resource, _store_id} ->
        # Dispatch the method call to the resource implementation
        result = Wasmex.Components.HostResource.call_method(resource, method, params)
        
        Logger.debug("Called method #{method} on resource #{resource_id}: #{inspect(result)}")
        
        {:reply, result, state}
        
      nil ->
        {:reply, {:error, "Resource not found: #{resource_id}"}, state}
    end
  end
  
  @impl true
  def handle_call({:drop, resource_id}, _from, state) do
    case Map.get(state.resources, resource_id) do
      {resource, store_id} ->
        # Call the drop function on the resource
        drop_result = Wasmex.Components.HostResource.drop(resource)
        
        # Remove from resources map
        resources = Map.delete(state.resources, resource_id)
        
        # Remove from store tracking
        store_resources = 
          Map.update(state.store_resources, store_id, MapSet.new(), fn set ->
            MapSet.delete(set, resource_id)
          end)
        
        new_state = %{state | resources: resources, store_resources: store_resources}
        
        Logger.debug("Dropped host resource #{resource_id}: #{inspect(drop_result)}")
        
        {:reply, :ok, new_state}
        
      nil ->
        # Resource already dropped or doesn't exist
        {:reply, :ok, state}
    end
  end
  
  @impl true
  def handle_call({:drop_store_resources, store_id}, _from, state) do
    # Get all resources for this store
    resource_ids = Map.get(state.store_resources, store_id, MapSet.new())
    
    # Drop each resource
    new_resources = 
      Enum.reduce(resource_ids, state.resources, fn resource_id, acc ->
        case Map.get(acc, resource_id) do
          {resource, ^store_id} ->
            # Call drop on the resource
            Wasmex.Components.HostResource.drop(resource)
            Logger.debug("Dropped host resource #{resource_id} for store #{store_id}")
            Map.delete(acc, resource_id)
            
          _ ->
            acc
        end
      end)
    
    # Remove the store from tracking
    new_store_resources = Map.delete(state.store_resources, store_id)
    
    new_state = %{state | resources: new_resources, store_resources: new_store_resources}
    
    Logger.debug("Dropped #{MapSet.size(resource_ids)} resources for store #{store_id}")
    
    {:reply, :ok, new_state}
  end
  
  # Helper functions
  
  defp get_store_id(store) do
    # Extract the store ID from the store reference
    # This will need to be implemented based on how stores track their IDs
    # For now, we'll use the reference as a unique identifier
    :erlang.phash2(store)
  end
end