defmodule Wasmex.Components.WasiIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  
  alias Wasmex.Components.{Store, Component, Instance}
  alias Wasmex.Wasi.WasiP2Options
  
  @moduletag :wasi_integration
  @moduletag timeout: :infinity
  
  @wasi_component_path "test/component_fixtures/wasi-test-component/target/wasm32-wasip2/release/wasi_test_component_final.wasm"
  
  setup_all do
    # Build the WASI test component using the build script
    build_cmd = "cd test/component_fixtures/wasi-test-component && ./build.sh"
    
    {output, exit_code} = System.cmd("sh", ["-c", build_cmd], stderr_to_stdout: true)
    
    if exit_code != 0 do
      IO.puts("Build output: #{output}")
      flunk("Failed to build WASI test component. Make sure you have wasm32-wasip2 target installed: rustup target add wasm32-wasip2")
    end
    
    # Ensure the component file exists
    unless File.exists?(@wasi_component_path) do
      flunk("Component file not found at #{@wasi_component_path}")
    end
    
    :ok
  end
  
  describe "WASI filesystem operations" do
    setup do
      temp_dir = System.tmp_dir!()
      test_dir = Path.join(temp_dir, "wasmex_wasi_test_#{:rand.uniform(1000000)}")
      File.mkdir_p!(test_dir)
      
      on_exit(fn ->
        File.rm_rf(test_dir)
      end)
      
      wasi_opts = %WasiP2Options{
        inherit_stdin: false,
        inherit_stdout: true,
        inherit_stderr: true,
        allow_filesystem: true,
        preopen_dirs: [test_dir],
        args: ["test-program"],
        env: %{"TEST_ENV" => "test_value"}
      }
      
      {:ok, store} = Store.new_wasi(wasi_opts)
      component_bytes = File.read!(@wasi_component_path)
      {:ok, component} = Component.new(store, component_bytes)
      {:ok, instance} = Instance.new(store, component, %{})
      
      {:ok, instance: instance, test_dir: test_dir}
    end
    
    test "can write and read files", %{instance: instance} do
      from = self()
      
      # Write a file
      :ok = Instance.call_function(
        instance, 
        ["test:wasi-component/wasi-tests", "test-filesystem-write"],
        ["test.txt", "Hello from WASI!"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, bytes_written}, ^from}, 5000
      assert bytes_written == 16  # "Hello from WASI!" is 16 bytes
      
      # Read the file back
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-read"],
        ["test.txt"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, content}, ^from}, 5000
      assert content == "Hello from WASI!"
      
      # Check if file exists
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-exists"],
        ["test.txt"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, exists}, ^from}, 5000
      assert exists == true
      
      # Check non-existent file
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-exists"],
        ["nonexistent.txt"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, exists}, ^from}, 5000
      assert exists == false
    end
    
    test "can delete files", %{instance: instance} do
      from = self()
      
      # Write a file
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-write"],
        ["delete_me.txt", "temporary file"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, _}, ^from}, 5000
      
      # Verify it exists
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-exists"],
        ["delete_me.txt"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, true}, ^from}, 5000
      
      # Delete it
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-delete"],
        ["delete_me.txt"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, _}, ^from}, 5000
      
      # Verify it's gone
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-exists"],
        ["delete_me.txt"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, false}, ^from}, 5000
    end
    
    test "can list directory contents", %{instance: instance} do
      from = self()
      
      # Create some files
      for i <- 1..3 do
        :ok = Instance.call_function(
          instance,
          ["test:wasi-component/wasi-tests", "test-filesystem-write"],
          ["file#{i}.txt", "content #{i}"],
          from
        )
        assert_receive {:returned_function_call, {:ok, _}, ^from}, 5000
      end
      
      # List directory
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-list-dir"],
        ["."],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, files}, ^from}, 5000
      assert is_list(files)
      assert "file1.txt" in files
      assert "file2.txt" in files
      assert "file3.txt" in files
    end
    
    test "filesystem is isolated to preopened directory", %{instance: instance, test_dir: test_dir} do
      from = self()
      
      # Try to write outside preopened directory (should fail)
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-filesystem-write"],
        ["../outside.txt", "should not work"],
        from
      )
      
      assert_receive {:returned_function_call, {:error, error}, ^from}, 5000
      assert error =~ "Failed" or error =~ "denied" or error =~ "not permitted"
      
      # Verify file was not created outside
      outside_path = Path.join(Path.dirname(test_dir), "outside.txt")
      refute File.exists?(outside_path)
    end
  end
  
  describe "WASI random operations" do
    setup do
      wasi_opts = %WasiP2Options{}
      {:ok, store} = Store.new_wasi(wasi_opts)
      component_bytes = File.read!(@wasi_component_path)
      {:ok, component} = Component.new(store, component_bytes)
      {:ok, instance} = Instance.new(store, component, %{})
      
      {:ok, instance: instance}
    end
    
    test "can generate random bytes", %{instance: instance} do
      from = self()
      
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-random-bytes"],
        [32],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, bytes}, ^from}, 5000
      assert is_list(bytes)
      assert length(bytes) == 32
      assert Enum.all?(bytes, &(&1 >= 0 and &1 <= 255))
      
      # Generate another set and verify they're different (extremely likely)
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-random-bytes"],
        [32],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, bytes2}, ^from}, 5000
      refute bytes == bytes2
    end
    
    test "can generate random u64", %{instance: instance} do
      from = self()
      
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-random-u64"],
        [],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, value}, ^from}, 5000
      assert is_integer(value)
      assert value >= 0
      
      # Generate multiple values and verify they're different
      values = for _ <- 1..10 do
        :ok = Instance.call_function(
          instance,
          ["test:wasi-component/wasi-tests", "test-random-u64"],
          [],
          from
        )
        assert_receive {:returned_function_call, {:ok, val}, ^from}, 5000
        val
      end
      
      # Should have at least some different values
      unique_values = Enum.uniq(values)
      assert length(unique_values) > 1
    end
  end
  
  describe "WASI clock operations" do
    setup do
      wasi_opts = %WasiP2Options{}
      {:ok, store} = Store.new_wasi(wasi_opts)
      component_bytes = File.read!(@wasi_component_path)
      {:ok, component} = Component.new(store, component_bytes)
      {:ok, instance} = Instance.new(store, component, %{})
      
      {:ok, instance: instance}
    end
    
    test "can get current time", %{instance: instance} do
      from = self()
      
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-clock-now"],
        [],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, nanos}, ^from}, 5000
      assert is_integer(nanos)
      assert nanos > 0
      
      # Verify time advances
      Process.sleep(10)
      
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-clock-now"],
        [],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, nanos2}, ^from}, 5000
      assert nanos2 > nanos
    end
    
    test "can get clock resolution", %{instance: instance} do
      from = self()
      
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-clock-resolution"],
        [],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, resolution}, ^from}, 5000
      assert is_integer(resolution)
      assert resolution > 0
    end
  end
  
  describe "WASI environment operations" do
    setup do
      wasi_opts = %WasiP2Options{
        args: ["myprogram", "--verbose", "input.txt"],
        env: %{
          "HOME" => "/home/wasi",
          "PATH" => "/usr/bin:/bin",
          "CUSTOM_VAR" => "custom_value"
        }
      }
      
      {:ok, store} = Store.new_wasi(wasi_opts)
      component_bytes = File.read!(@wasi_component_path)
      {:ok, component} = Component.new(store, component_bytes)
      {:ok, instance} = Instance.new(store, component, %{})
      
      {:ok, instance: instance}
    end
    
    test "can access environment variables", %{instance: instance} do
      from = self()
      
      # Get existing env var
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-get-env"],
        ["CUSTOM_VAR"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, {:some, value}}, ^from}, 5000
      assert value == "custom_value"
      
      # Get non-existent env var
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-get-env"],
        ["NONEXISTENT"],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, :none}, ^from}, 5000
    end
    
    test "can access command-line arguments", %{instance: instance} do
      from = self()
      
      :ok = Instance.call_function(
        instance,
        ["test:wasi-component/wasi-tests", "test-get-args"],
        [],
        from
      )
      
      assert_receive {:returned_function_call, {:ok, args}, ^from}, 5000
      assert args == ["myprogram", "--verbose", "input.txt"]
    end
  end
  
  describe "WASI stdio operations" do
    setup do
      wasi_opts = %WasiP2Options{
        inherit_stdout: true,
        inherit_stderr: true
      }
      
      {:ok, store} = Store.new_wasi(wasi_opts)
      component_bytes = File.read!(@wasi_component_path)
      {:ok, component} = Component.new(store, component_bytes)
      {:ok, instance} = Instance.new(store, component, %{})
      
      {:ok, instance: instance}
    end
    
    test "can write to stdout", %{instance: instance} do
      from = self()
      
      output = capture_io(fn ->
        :ok = Instance.call_function(
          instance,
          ["test:wasi-component/wasi-tests", "test-print-stdout"],
          ["Hello from WASI stdout!"],
          from
        )
        
        assert_receive {:returned_function_call, {:ok, _}, ^from}, 5000
      end)
      
      assert output == "Hello from WASI stdout!"
    end
    
    test "can write to stderr", %{instance: instance} do
      from = self()
      
      output = capture_io(:stderr, fn ->
        :ok = Instance.call_function(
          instance,
          ["test:wasi-component/wasi-tests", "test-print-stderr"],
          ["Error from WASI stderr!"],
          from
        )
        
        assert_receive {:returned_function_call, {:ok, _}, ^from}, 5000
      end)
      
      assert output == "Error from WASI stderr!"
    end
  end
  
  describe "WASI configuration restrictions" do
    test "filesystem access can be disabled" do
      wasi_opts = %WasiP2Options{
        allow_filesystem: false
      }
      
      {:ok, store} = Store.new_wasi(wasi_opts)
      component_bytes = File.read!(@wasi_component_path)
      
      # Component should fail to instantiate without filesystem access
      # if it imports filesystem interfaces
      result = Component.new(store, component_bytes)
      
      # This might succeed or fail depending on how wasmtime handles it
      # The important part is that filesystem operations won't work
      case result do
        {:ok, component} ->
          {:ok, instance} = Instance.new(store, component, %{})
          from = self()
          
          # Try to write a file (should fail)
          :ok = Instance.call_function(
            instance,
            ["test:wasi-component/wasi-tests", "test-filesystem-write"],
            ["test.txt", "should fail"],
            from
          )
          
          assert_receive {:returned_function_call, {:error, error}, ^from}, 5000
          assert error =~ "No preopened directories" or error =~ "denied"
          
        {:error, _error} ->
          # Component failed to instantiate without filesystem - also acceptable
          assert true
      end
    end
  end
end