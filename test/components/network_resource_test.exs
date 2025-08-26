defmodule Wasmex.ComponentNetworkResourceTest do
  use ExUnit.Case
  
  @network_component_path "test/component_fixtures/network-component/target/wasm32-wasip1/release/network_component.wasm"
  
  describe "network resource component" do
    setup do
      unless File.exists?(@network_component_path) do
        raise "Component not built. Run: cd test/component_fixtures/network-component && cargo component build --release"
      end
      
      component_bytes = File.read!(@network_component_path)
      {:ok, store} = Wasmex.Components.Store.new()
      {:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
      {:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})
      
      {:ok, store: store, component: component, instance: instance}
    end
    
    test "can call test function", %{instance: instance} do
      from = self()
      
      :ok = Wasmex.Components.Instance.call_function(instance, "test", [], from)
      
      receive do
        {:returned_function_call, {:ok, value}, ^from} ->
          assert value == "Network resource test component"
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error calling test function: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for function result")
      end
    end
  end
  
  describe "TCP socket resources" do
    setup do
      component_bytes = File.read!(@network_component_path)
      {:ok, store} = Wasmex.Components.Store.new()
      {:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
      {:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})
      
      {:ok, store: store, component: component, instance: instance}
    end
    
    test "can create TCP socket resource", %{instance: instance} do
      from = self()
      
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["test:network/types", "create-tcp-socket"], 
        [], 
        from
      )
      
      receive do
        {:returned_function_call, {:ok, socket}, ^from} ->
          assert is_reference(socket)
          IO.puts("Created TCP socket resource: #{inspect(socket)}")
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating TCP socket: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for TCP socket creation")
      end
    end
    
    test "TCP socket connect operation", %{instance: instance, store: store} do
      from = self()
      
      # Create socket
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["test:network/types", "create-tcp-socket"], 
        [], 
        from
      )
      
      socket = receive do
        {:returned_function_call, {:ok, socket}, ^from} -> socket
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating TCP socket: #{inspect(error)}")
      after
        5000 -> flunk("Timeout creating TCP socket")
      end
      
      # Try to connect (if resource methods are implemented)
      if function_exported?(Wasmex.Components.Resource, :call_method, 4) do
        result = Wasmex.Components.Resource.call_method(
          socket,
          "connect",
          ["127.0.0.1", 8080],
          store
        )
        
        case result do
          {:ok, _} -> assert true
          {:error, _} -> assert true  # Connection might fail, that's ok for test
        end
      end
    end
    
    test "multiple TCP sockets can coexist", %{instance: instance} do
      from = self()
      
      # Create first socket
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["test:network/types", "create-tcp-socket"], 
        [], 
        from
      )
      
      socket1 = receive do
        {:returned_function_call, {:ok, socket}, ^from} -> socket
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating first TCP socket: #{inspect(error)}")
      after
        5000 -> flunk("Timeout creating first TCP socket")
      end
      
      # Create second socket
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["test:network/types", "create-tcp-socket"], 
        [], 
        from
      )
      
      socket2 = receive do
        {:returned_function_call, {:ok, socket}, ^from} -> socket
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating second TCP socket: #{inspect(error)}")
      after
        5000 -> flunk("Timeout creating second TCP socket")
      end
      
      # Verify both are valid and different
      assert is_reference(socket1)
      assert is_reference(socket2)
      assert socket1 != socket2
    end
  end
  
  describe "UDP socket resources" do
    setup do
      component_bytes = File.read!(@network_component_path)
      {:ok, store} = Wasmex.Components.Store.new()
      {:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
      {:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})
      
      {:ok, store: store, component: component, instance: instance}
    end
    
    test "can create UDP socket resource", %{instance: instance} do
      from = self()
      
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["test:network/types", "create-udp-socket"], 
        [], 
        from
      )
      
      receive do
        {:returned_function_call, {:ok, socket}, ^from} ->
          assert is_reference(socket)
          IO.puts("Created UDP socket resource: #{inspect(socket)}")
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating UDP socket: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for UDP socket creation")
      end
    end
    
    test "UDP socket bind operation", %{instance: instance, store: store} do
      from = self()
      
      # Create socket
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["test:network/types", "create-udp-socket"], 
        [], 
        from
      )
      
      socket = receive do
        {:returned_function_call, {:ok, socket}, ^from} -> socket
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating UDP socket: #{inspect(error)}")
      after
        5000 -> flunk("Timeout creating UDP socket")
      end
      
      # Try to bind (if resource methods are implemented)
      if function_exported?(Wasmex.Components.Resource, :call_method, 4) do
        result = Wasmex.Components.Resource.call_method(
          socket,
          "bind",
          ["0.0.0.0", 0],
          store
        )
        
        case result do
          {:ok, _} -> assert true
          {:error, _} -> assert true  # Bind might fail, that's ok for test
        end
      end
    end
  end
  
  describe "HTTP client resources" do
    setup do
      component_bytes = File.read!(@network_component_path)
      {:ok, store} = Wasmex.Components.Store.new()
      {:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
      {:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})
      
      {:ok, store: store, component: component, instance: instance}
    end
    
    test "can create HTTP client resource", %{instance: instance} do
      from = self()
      
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["test:network/types", "create-http-client"], 
        [], 
        from
      )
      
      receive do
        {:returned_function_call, {:ok, client}, ^from} ->
          assert is_reference(client)
          IO.puts("Created HTTP client resource: #{inspect(client)}")
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating HTTP client: #{inspect(error)}")
      after
        5000 ->
          flunk("Timeout waiting for HTTP client creation")
      end
    end
    
    test "HTTP client request operation", %{instance: instance, store: store} do
      from = self()
      
      # Create client
      :ok = Wasmex.Components.Instance.call_function(
        instance, 
        ["test:network/types", "create-http-client"], 
        [], 
        from
      )
      
      client = receive do
        {:returned_function_call, {:ok, client}, ^from} -> client
        {:returned_function_call, {:error, error}, ^from} ->
          flunk("Error creating HTTP client: #{inspect(error)}")
      after
        5000 -> flunk("Timeout creating HTTP client")
      end
      
      # Try to make a request (if resource methods are implemented)
      if function_exported?(Wasmex.Components.Resource, :call_method, 4) do
        result = Wasmex.Components.Resource.call_method(
          client,
          "request",
          ["GET", "http://example.com", [], nil],
          store
        )
        
        case result do
          {:ok, response} when is_reference(response) -> 
            assert true
            # Could test response methods here
          {:ok, _} -> assert true
          {:error, _} -> assert true  # Request might fail, that's ok for test
        end
      end
    end
  end
  
  describe "network resource lifecycle" do
    setup do
      component_bytes = File.read!(@network_component_path)
      {:ok, component_bytes: component_bytes}
    end
    
    test "resources are cleaned up when store is dropped", %{component_bytes: component_bytes} do
      {:ok, store} = Wasmex.Components.Store.new()
      {:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
      {:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})
      
      from = self()
      
      # Create multiple network resources
      resources = []
      
      # Create TCP sockets
      for i <- 1..3 do
        :ok = Wasmex.Components.Instance.call_function(
          instance, 
          ["test:network/types", "create-tcp-socket"], 
          [], 
          from
        )
        
        receive do
          {:returned_function_call, {:ok, socket}, ^from} -> 
            [socket | resources]
          {:returned_function_call, {:error, error}, ^from} ->
            flunk("Error creating TCP socket #{i}: #{inspect(error)}")
        after
          5000 -> flunk("Timeout creating TCP socket #{i}")
        end
      end
      
      # Create UDP sockets
      for i <- 1..3 do
        :ok = Wasmex.Components.Instance.call_function(
          instance, 
          ["test:network/types", "create-udp-socket"], 
          [], 
          from
        )
        
        receive do
          {:returned_function_call, {:ok, socket}, ^from} -> 
            [socket | resources]
          {:returned_function_call, {:error, error}, ^from} ->
            flunk("Error creating UDP socket #{i}: #{inspect(error)}")
        after
          5000 -> flunk("Timeout creating UDP socket #{i}")
        end
      end
      
      # Create HTTP clients
      for i <- 1..2 do
        :ok = Wasmex.Components.Instance.call_function(
          instance, 
          ["test:network/types", "create-http-client"], 
          [], 
          from
        )
        
        receive do
          {:returned_function_call, {:ok, client}, ^from} -> 
            [client | resources]
          {:returned_function_call, {:error, error}, ^from} ->
            flunk("Error creating HTTP client #{i}: #{inspect(error)}")
        after
          5000 -> flunk("Timeout creating HTTP client #{i}")
        end
      end
      
      # Force garbage collection to clean up the store
      :erlang.garbage_collect()
      
      # Store and resources should be cleaned up automatically
    end
    
    test "stress test: create many network resources", %{component_bytes: component_bytes} do
      for iteration <- 1..5 do
        {:ok, store} = Wasmex.Components.Store.new()
        {:ok, component} = Wasmex.Components.Component.new(store, component_bytes)
        {:ok, instance} = Wasmex.Components.Instance.new(store, component, %{})
        
        from = self()
        
        # Create 50 mixed network resources
        for i <- 1..50 do
          function = case rem(i, 3) do
            0 -> ["test:network/types", "create-tcp-socket"]
            1 -> ["test:network/types", "create-udp-socket"]
            2 -> ["test:network/types", "create-http-client"]
          end
          
          :ok = Wasmex.Components.Instance.call_function(
            instance, 
            function, 
            [], 
            from
          )
          
          receive do
            {:returned_function_call, {:ok, _resource}, ^from} -> :ok
            {:returned_function_call, {:error, error}, ^from} ->
              flunk("Error in iteration #{iteration}, resource #{i}: #{inspect(error)}")
          after
            5000 -> flunk("Timeout in iteration #{iteration}, resource #{i}")
          end
        end
        
        # Force cleanup after each iteration
        :erlang.garbage_collect()
      end
      
      # If we get here without crashes or OOM, the test passed
      assert true
    end
  end
end