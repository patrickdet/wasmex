defmodule Wasmex.ComponentResourceMethodsTest do
  use ExUnit.Case
  
  @counter_component_path "test/component_fixtures/counter-component/target/wasm32-wasip1/release/counter_component.wasm"
  
  describe "counter resource methods" do
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
    
    test "can call increment method on counter resource", %{store: store, instance: instance} do
      %{resource: store_resource} = store
      %{instance_resource: instance_resource} = instance
      from = self()
      
      # Create a counter with initial value 5
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["component:counter/types", "make-counter"], 
        [5], 
        from
      )
      
      counter = receive do
        {:returned_function_call, {:ok, counter}, ^from} ->
          assert is_reference(counter)
          counter
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating counter: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for counter creation")
      end
      
      # Call increment method
      :ok = Wasmex.Native.resource_call_method(
        store_resource,
        instance_resource,
        counter,
        ["component:counter/types"],
        "increment",
        [],
        from
      )
      
      receive do
        {:returned_function_call, {:ok, value}, ^from} ->
          assert value == 6
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error calling increment: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for increment result")
      end
    end
    
    test "can call get_value method on counter resource", %{store: store, instance: instance} do
      %{resource: store_resource} = store
      %{instance_resource: instance_resource} = instance
      from = self()
      
      # Create a counter with initial value 10
      :ok = Wasmex.Components.Instance.call_function(
        instance,
        ["component:counter/types", "make-counter"],
        [10],
        from
      )
      
      counter = receive do
        {:returned_function_call, {:ok, counter}, ^from} ->
          counter
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating counter: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for counter creation")
      end
      
      # Call get-value method
      :ok = Wasmex.Native.resource_call_method(
        store_resource,
        instance_resource,
        counter,
        ["component:counter/types"],
        "get-value",
        [],
        from
      )
      
      receive do
        {:returned_function_call, {:ok, value}, ^from} ->
          assert value == 10
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error calling get-value: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for get-value result")
      end
    end
    
    test "can call reset method on counter resource", %{store: store, instance: instance} do
      %{resource: store_resource} = store
      %{instance_resource: instance_resource} = instance
      from = self()
      
      # Create a counter with initial value 5
      :ok = Wasmex.Components.Instance.call_function(
        instance,
        ["component:counter/types", "make-counter"],
        [5],
        from
      )
      
      counter = receive do
        {:returned_function_call, {:ok, counter}, ^from} ->
          counter
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating counter: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for counter creation")
      end
      
      # Call reset method with new value 100
      :ok = Wasmex.Native.resource_call_method(
        store_resource,
        instance_resource,
        counter,
        ["component:counter/types"],
        "reset",
        [100],
        from
      )
      
      receive do
        {:returned_function_call, :ok, ^from} ->
          # reset returns no value, so just :ok
          :ok
        {:returned_function_call, {:ok, _}, ^from} ->
          :ok
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error calling reset: #{inspect(error)}")
        msg ->
          flunk("Unexpected message: #{inspect(msg)}")
      after
        5000 ->
          flunk("Timeout waiting for reset result")
      end
      
      # Verify the value was reset
      :ok = Wasmex.Native.resource_call_method(
        store_resource,
        instance_resource,
        counter,
        ["component:counter/types"],
        "get-value",
        [],
        from
      )
      
      receive do
        {:returned_function_call, {:ok, value}, ^from} ->
          assert value == 100
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error calling get-value: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for get-value result")
      end
    end
    
    test "can chain multiple method calls", %{store: store, instance: instance} do
      %{resource: store_resource} = store
      %{instance_resource: instance_resource} = instance
      from = self()
      
      # Create a counter with initial value 0
      :ok = Wasmex.Components.Instance.call_function(
        instance,
        ["component:counter/types", "make-counter"],
        [0],
        from
      )
      
      counter = receive do
        {:returned_function_call, {:ok, counter}, ^from} ->
          counter
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating counter: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for counter creation")
      end
      
      # Increment multiple times
      for expected <- 1..5 do
        :ok = Wasmex.Native.resource_call_method(
          store_resource,
          instance_resource,
          counter,
          ["component:counter/types"],
          "increment",
          [],
          from
        )
        
        receive do
          {:returned_function_call, {:ok, value}, ^from} ->
            assert value == expected
          {:returned_function_call, {:error, error}, ^from} ->
            flunk("Error calling increment: #{inspect(error)}")
        after
          5000 ->
            flunk("Timeout waiting for increment result")
        end
      end
      
      # Final value should be 5
      :ok = Wasmex.Native.resource_call_method(
        store_resource,
        instance_resource,
        counter,
        ["component:counter/types"],
        "get-value",
        [],
        from
      )
      
      receive do
        {:returned_function_call, {:ok, value}, ^from} ->
          assert value == 5
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error calling get-value: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for get-value result")
      end
    end
    
    test "error when calling method on resource from wrong store", %{instance: instance} do
      %{instance_resource: instance_resource} = instance
      from = self()
      
      # Create a counter in the original store
      :ok = Wasmex.Components.Instance.call_function(
        instance,
        ["component:counter/types", "make-counter"],
        [5],
        from
      )
      
      counter = receive do
        {:returned_function_call, {:ok, counter}, ^from} ->
          counter
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating counter: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for counter creation")
      end
      
      # Create a different store and instance
      {:ok, other_store} = Wasmex.Components.Store.new()
      component_bytes = File.read!(@counter_component_path)
      {:ok, other_component} = Wasmex.Components.Component.new(other_store, component_bytes)
      {:ok, other_instance} = Wasmex.Components.Instance.new(other_store, other_component, %{})
      
      # Try to use the resource from the first store with the second store
      %{resource: other_store_resource} = other_store
      %{instance_resource: other_instance_resource} = other_instance
      
      :ok = Wasmex.Native.resource_call_method(
        other_store_resource,
        other_instance_resource,
        counter,
        ["component:counter/types"],
        "increment",
        [],
        from
      )
      
      receive do
        {:returned_function_call, {:error, error}, ^from} ->
          assert error =~ "Resource does not belong to this store"
        {:returned_function_call, {:ok, _}, ^from} ->
          flunk("Should have failed with wrong store error")
      after
        5000 ->
          flunk("Timeout waiting for error")
      end
    end
  end
end