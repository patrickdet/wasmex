defmodule Wasmex.Components.Resource do
  @moduledoc """
  Represents a WASI component resource.
  
  Resources are handles to entities that exist outside of the component,
  such as files, sockets, or HTTP connections. They can be owned or borrowed.
  
  Owned resources must be explicitly dropped when no longer needed.
  Borrowed resources are temporary loans and should not be dropped by the borrower.
  """
  
  @type ownership :: :owned | :borrowed
  
  @type t :: %__MODULE__{
    resource: binary(),
    type: ownership(),
    type_name: String.t(),
    store_ref: reference(),
    reference: reference()
  }
  
  defstruct [:resource, :type, :type_name, :store_ref, :reference]
  
  @doc """
  Wraps a native resource into an Elixir struct.
  """
  def __wrap_resource__(native_resource, type, type_name, store_ref) do
    %__MODULE__{
      resource: native_resource,
      type: type,
      type_name: type_name,
      store_ref: store_ref,
      reference: make_ref()
    }
  end
  
  @doc """
  Drops an owned resource, releasing its associated state.
  
  Returns `:ok` on success, or `{:error, reason}` on failure.
  
  ## Examples
  
      iex> resource = %Wasmex.Components.Resource{type: :borrowed}
      iex> Wasmex.Components.Resource.drop(resource)
      {:error, "Cannot drop a borrowed resource"}
  
  ## Errors
  
  - Returns error if the resource is borrowed (only owned resources can be dropped)
  - Returns error if the resource has already been dropped
  - Returns error if the store is no longer available
  """
  def drop(%__MODULE__{resource: resource, type: :owned, store_ref: store_ref}) do
    case Wasmex.Native.resource_drop(resource, store_ref) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end
  
  def drop(%__MODULE__{type: :borrowed}) do
    {:error, "Cannot drop a borrowed resource"}
  end
  
  @doc """
  Checks if a resource is owned.
  """
  def owned?(%__MODULE__{type: type}), do: type == :owned
  
  @doc """
  Checks if a resource is borrowed.
  """
  def borrowed?(%__MODULE__{type: type}), do: type == :borrowed
  
  @doc """
  Gets the type name of the resource.
  """
  def type_name(%__MODULE__{type_name: name}), do: name
end