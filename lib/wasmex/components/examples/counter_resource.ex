defmodule Wasmex.Components.Examples.CounterResource do
  @moduledoc """
  Example implementation of a host-defined counter resource.
  
  This demonstrates how to create a simple stateful resource that can be
  passed to and used by WASM components.
  """
  
  defstruct [:value, :name]
  
  @doc """
  Creates a new counter resource with an initial value.
  """
  def new(initial_value \\ 0, name \\ "default") do
    %__MODULE__{value: initial_value, name: name}
  end
  
  defimpl Wasmex.Components.HostResource do
    def type_name(_resource), do: "example-counter"
    
    def call_method(resource, "increment", []) do
      new_value = resource.value + 1
      updated = %{resource | value: new_value}
      {:ok, {updated, new_value}}
    end
    
    def call_method(resource, "increment", [amount]) when is_integer(amount) do
      new_value = resource.value + amount
      updated = %{resource | value: new_value}
      {:ok, {updated, new_value}}
    end
    
    def call_method(resource, "decrement", []) do
      new_value = resource.value - 1
      updated = %{resource | value: new_value}
      {:ok, {updated, new_value}}
    end
    
    def call_method(resource, "get-value", []) do
      {:ok, resource.value}
    end
    
    def call_method(resource, "reset", []) do
      updated = %{resource | value: 0}
      {:ok, {updated, nil}}
    end
    
    def call_method(resource, "get-name", []) do
      {:ok, resource.name}
    end
    
    def call_method(resource, "set-name", [new_name]) when is_binary(new_name) do
      updated = %{resource | name: new_name}
      {:ok, {updated, nil}}
    end
    
    def call_method(_resource, method, params) do
      {:error, "Unknown method: #{method} with params: #{inspect(params)}"}
    end
    
    def drop(resource) do
      # For this simple example, just log the drop
      require Logger
      Logger.debug("Dropping counter resource: #{resource.name} with value: #{resource.value}")
      :ok
    end
  end
end