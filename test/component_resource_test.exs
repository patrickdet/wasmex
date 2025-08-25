defmodule Wasmex.ComponentResourceTest do
  use ExUnit.Case
  
  @counter_component_path "test/component_fixtures/counter-component/target/wasm32-wasip1/release/counter_component.wasm"
  
  describe "counter resource component" do
    setup do
      # Check if component exists
      unless File.exists?(@counter_component_path) do
        raise "Component not built. Run: cd test/component_fixtures/counter-component && cargo component build --release"
      end
      
      # Read the component bytes
      component_bytes = File.read!(@counter_component_path)
      
      # Create a store
      {:ok, store} = Wasmex.Components.Store.new()
      
      # Load the component  
      {:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
      
      # Create an instance
      {:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})
      
      {:ok, store: store, component: component, instance: instance}
    end
    
    test "can call test function", %{instance: instance} do
      # Call the test function with proper from parameter
      from = self()
      
      # This is async - it sends the result back as a message
      :ok = Wasmex.Components.Instance.call_function(instance, "test", [], from)
      
      # Wait for the result
      receive do
        {:returned_function_call, {:ok, value}, ^from} ->
          assert value == "Counter resource test component"
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error calling test function: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for function result")
      end
    end
    
    test "can create counter resource", %{instance: instance} do
      from = self()
      
      # Create a counter with initial value 5
      :ok = Wasmex.Components.Instance.call_function(instance, ["component:counter/types", "make-counter"], [5], from)
      
      receive do
        {:returned_function_call, {:ok, counter}, ^from} ->
          # Verify it's a resource (will be a reference in Elixir)
          assert is_reference(counter)
          IO.puts("Created counter resource: #{inspect(counter)}")
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating counter: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for counter creation")
      end
    end
  end
  
  describe "basic component loading" do
    test "component file exists" do
      assert File.exists?(@counter_component_path), 
             "Component not found. Build with: cd test/component_fixtures/counter-component && cargo component build --release"
    end
    
    test "can read component bytes" do
      bytes = File.read!(@counter_component_path)
      assert byte_size(bytes) > 0
      # WASM magic number
      <<0x00, 0x61, 0x73, 0x6D, _rest::binary>> = bytes
    end
  end
end