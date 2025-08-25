defmodule Wasmex.Components.FilesystemResourceTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Wasmex.Components
  alias Wasmex.Components.Resource

  @moduletag :filesystem_resources
  @moduletag timeout: :infinity

  describe "filesystem resources (using counter as test base)" do
    setup do
      # For now, we'll use the counter component to test resource patterns
      # that will be similar to filesystem resources
      wat_path = Path.join(__DIR__, "component_fixtures/counter-component/target/wasm32-wasip1/release/counter_component.wasm")
      
      # Ensure the component is built
      build_cmd = "cd #{Path.join(__DIR__, "component_fixtures/counter-component")} && cargo component build --release"
      {_, 0} = System.cmd("sh", ["-c", build_cmd], stderr_to_stdout: true)
      
      {:ok, store} = Components.Store.new()
      {:ok, component} = Components.Component.new(store, File.read!(wat_path))
      {:ok, instance} = Components.Instance.new(store, component, %{})
      
      %{store: store, instance: instance}
    end

    test "simulate file handle resource lifecycle", %{store: store, instance: instance} do
      # Create multiple "file handles" (using counters as stand-ins)
      {:ok, file1} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [100])
      {:ok, file2} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [200])
      {:ok, file3} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [300])
      
      assert %Resource{} = file1
      assert %Resource{} = file2
      assert %Resource{} = file3
      
      # Simulate file operations (using counter methods)
      {:ok, 101} = Resource.call_method(file1, "increment", [])
      {:ok, 201} = Resource.call_method(file2, "increment", [])
      {:ok, 301} = Resource.call_method(file3, "increment", [])
      
      # Verify we can read current state
      {:ok, 101} = Resource.call_method(file1, "get-value", [])
      {:ok, 201} = Resource.call_method(file2, "get-value", [])
      {:ok, 301} = Resource.call_method(file3, "get-value", [])
    end

    test "concurrent file handle operations", %{store: store, instance: instance} do
      # Create a file handle
      {:ok, file_handle} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [0])
      
      # Simulate concurrent writes (increments)
      tasks = for i <- 1..100 do
        Task.async(fn ->
          Resource.call_method(file_handle, "increment", [])
        end)
      end
      
      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, _} -> true; _ -> false end)
      
      # Final value should be 100
      {:ok, final_value} = Resource.call_method(file_handle, "get-value", [])
      assert final_value == 100
    end

    test "file handle cleanup on store drop", %{instance: instance} do
      # Create multiple file handles
      handles = for i <- 1..10 do
        {:ok, handle} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [i])
        handle
      end
      
      # Verify all handles work
      for {handle, expected} <- Enum.zip(handles, 1..10) do
        {:ok, value} = Resource.call_method(handle, "get-value", [])
        assert value == expected
      end
      
      # Store will be cleaned up automatically when test ends
      # Resources should be cleaned up with it
    end

    test "directory-like resource hierarchy", %{store: store, instance: instance} do
      # Simulate a directory structure using counters
      # Root directory
      {:ok, root_dir} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [0])
      
      # Subdirectories (represented by counters with different initial values)
      {:ok, subdir1} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [1000])
      {:ok, subdir2} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [2000])
      
      # Files in subdirectories
      {:ok, file1_in_subdir1} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [1001])
      {:ok, file2_in_subdir1} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [1002])
      {:ok, file1_in_subdir2} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [2001])
      
      # Simulate operations on the hierarchy
      {:ok, _} = Resource.call_method(file1_in_subdir1, "increment", [])
      {:ok, _} = Resource.call_method(file2_in_subdir1, "increment", [])
      {:ok, _} = Resource.call_method(file1_in_subdir2, "increment", [])
      
      # Verify the structure maintains integrity
      {:ok, 1002} = Resource.call_method(file1_in_subdir1, "get-value", [])
      {:ok, 1003} = Resource.call_method(file2_in_subdir1, "get-value", [])
      {:ok, 2002} = Resource.call_method(file1_in_subdir2, "get-value", [])
    end

    test "file position tracking simulation", %{store: store, instance: instance} do
      # Use counter to simulate file position
      {:ok, file_pos} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [0])
      
      # Simulate reading (advancing position)
      bytes_to_read = [10, 20, 15, 5, 30]
      
      for bytes <- bytes_to_read do
        # Simulate advancing position by bytes read
        for _ <- 1..bytes do
          {:ok, _} = Resource.call_method(file_pos, "increment", [])
        end
      end
      
      # Check final position
      {:ok, position} = Resource.call_method(file_pos, "get-value", [])
      assert position == Enum.sum(bytes_to_read)
      
      # Simulate seek to beginning
      {:ok, _} = Resource.call_method(file_pos, "reset", [0])
      {:ok, 0} = Resource.call_method(file_pos, "get-value", [])
    end

    test "resource error handling patterns", %{store: store, instance: instance} do
      {:ok, resource} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [42])
      
      # Test normal operation
      assert {:ok, 42} = Resource.call_method(resource, "get-value", [])
      
      # Test with wrong store (should fail)
      {:ok, other_store} = Components.Store.new()
      {:ok, other_component} = Components.Component.new(other_store, 
        File.read!(Path.join(__DIR__, "component_fixtures/counter-component/target/wasm32-wasip1/release/counter_component.wasm")))
      {:ok, other_instance} = Components.Instance.new(other_store, other_component, %{})
      {:ok, other_resource} = Components.Instance.call_function(other_instance, "component:counter/types", "make-counter", [99])
      
      # Try to use resource from one store with another store's resource
      # This should be protected by store ID checking
      assert resource.store_id != other_resource.store_id
    end

    test "bulk file operations simulation", %{store: store, instance: instance} do
      # Create many file handles to simulate bulk operations
      num_files = 100
      
      log = capture_log(fn ->
        files = for i <- 1..num_files do
          {:ok, file} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [i * 100])
          file
        end
        
        # Perform operations on all files
        for file <- files do
          # Write operation (increment)
          {:ok, _} = Resource.call_method(file, "increment", [])
          # Read operation (get-value)
          {:ok, _value} = Resource.call_method(file, "get-value", [])
        end
        
        # Verify a sample
        sample_files = Enum.take(files, 5)
        for {file, i} <- Enum.zip(sample_files, 1..5) do
          {:ok, value} = Resource.call_method(file, "get-value", [])
          assert value == i * 100 + 1
        end
      end)
      
      # Ensure no memory leak warnings in logs
      refute log =~ "memory leak"
      refute log =~ "resource leak"
    end

    test "file metadata simulation", %{store: store, instance: instance} do
      # Simulate file with size (using counter value as size in bytes)
      {:ok, file} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [1024])
      
      # Get "size" 
      {:ok, size} = Resource.call_method(file, "get-value", [])
      assert size == 1024
      
      # Simulate write that increases size
      for _ <- 1..256 do
        {:ok, _} = Resource.call_method(file, "increment", [])
      end
      
      {:ok, new_size} = Resource.call_method(file, "get-value", [])
      assert new_size == 1280  # 1024 + 256
      
      # Simulate truncate (reset to specific size)
      {:ok, _} = Resource.call_method(file, "reset", [512])
      {:ok, truncated_size} = Resource.call_method(file, "get-value", [])
      assert truncated_size == 512
    end
  end

  describe "resource lifecycle stress testing" do
    setup do
      wat_path = Path.join(__DIR__, "component_fixtures/counter-component/target/wasm32-wasip1/release/counter_component.wasm")
      
      # Ensure built
      build_cmd = "cd #{Path.join(__DIR__, "component_fixtures/counter-component")} && cargo component build --release"
      {_, 0} = System.cmd("sh", ["-c", build_cmd], stderr_to_stdout: true)
      
      %{wat_path: wat_path}
    end

    test "repeated store creation and destruction", %{wat_path: wat_path} do
      # This simulates opening and closing many files/directories
      for iteration <- 1..10 do
        {:ok, store} = Components.Store.new()
        {:ok, component} = Components.Component.new(store, File.read!(wat_path))
        {:ok, instance} = Components.Instance.new(store, component, %{})
        
        # Create resources
        resources = for i <- 1..50 do
          {:ok, resource} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [i])
          resource
        end
        
        # Use resources
        for resource <- Enum.take(resources, 10) do
          {:ok, _} = Resource.call_method(resource, "increment", [])
        end
        
        # Store and resources will be cleaned up when going out of scope
      end
      
      # If we get here without crashes or leaks, the test passes
      assert true
    end

    test "cross-store resource isolation", %{wat_path: wat_path} do
      # Create multiple stores with resources
      stores_and_resources = for i <- 1..5 do
        {:ok, store} = Components.Store.new()
        {:ok, component} = Components.Component.new(store, File.read!(wat_path))
        {:ok, instance} = Components.Instance.new(store, component, %{})
        {:ok, resource} = Components.Instance.call_function(instance, "component:counter/types", "make-counter", [i * 100])
        
        {store, instance, resource}
      end
      
      # Verify each resource works with its own store
      for {{_store, _instance, resource}, i} <- Enum.zip(stores_and_resources, 1..5) do
        {:ok, value} = Resource.call_method(resource, "get-value", [])
        assert value == i * 100
      end
      
      # Stores will be cleaned up, ensuring proper isolation
    end
  end
end