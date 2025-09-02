defmodule Wasmex.Test.Support.Examples.CounterComponentResource do
  @moduledoc """
  Example of using ResourceComponentServer for a cleaner resource API.

  This module demonstrates how to use the new ResourceComponentServer macro
  to automatically generate wrapper functions from a WIT file, similar to
  how ComponentServer works for regular functions.

  ## Usage

  ```elixir
  # Start the resource
  {:ok, pid} = CounterComponentResource.start_link(42)

  # Use the auto-generated wrapper functions
  CounterComponentResource.increment(pid)      # Returns: 43
  CounterComponentResource.get_value(pid)      # Returns: 43
  CounterComponentResource.reset(pid, 0)       # Returns: :ok
  CounterComponentResource.get_stats(pid)      # Returns: %{value: 0, operations: 3}
  ```

  The wrapper functions are generated automatically from the WIT file,
  providing a clean, idiomatic Elixir API without manual boilerplate.
  """

  use Wasmex.Components.ResourceComponentServer,
    wit: "test/component_fixtures/counter-component/wit/world.wit",
    resource: "counter"

  require Logger

  defmodule State do
    @moduledoc false
    defstruct value: 0, operation_count: 0, name: "default"
  end

  # Resource initialization - the macro calls init_resource which calls this

  def init(initial_value) when is_integer(initial_value) do
    Logger.debug("Initializing CounterComponentResource with value: #{initial_value}")
    {:ok, %State{value: initial_value}}
  end

  def init(%{initial_value: initial} = opts) do
    name = Map.get(opts, :name, "default")
    {:ok, %State{value: initial, name: name}}
  end

  def init(_), do: {:ok, %State{}}

  # Method handlers
  def handle_method("increment", [], state) do
    new_value = state.value + 1
    new_state = %State{state | value: new_value, operation_count: state.operation_count + 1}
    {:reply, new_value, new_state}
  end

  def handle_method("get-value", [], state) do
    {:reply, state.value, state}
  end

  def handle_method("reset", [value], state) do
    new_state = %State{state | value: value, operation_count: state.operation_count + 1}
    {:noreply, new_state}
  end

  # Additional methods not in WIT file (still accessible via call_method)
  def handle_method("get-stats", [], state) do
    stats = %{
      value: state.value,
      operations: state.operation_count,
      name: state.name
    }

    {:reply, stats, state}
  end

  def handle_method(method, params, state) do
    Logger.warning("Unknown method: #{method} with params: #{inspect(params)}")
    {:error, "Unknown method: #{method}", state}
  end

  # Optional cleanup callback - called by the macro's terminate/2
  def on_terminate(reason, state) do
    Logger.debug(
      "CounterComponentResource terminating: #{state.name} " <>
        "with final value: #{state.value}, " <>
        "operations: #{state.operation_count}, " <>
        "reason: #{inspect(reason)}"
    )

    :ok
  end
end
