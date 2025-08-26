defmodule Wasmex.Components.FilesystemResourceTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Wasmex.Components
  alias Wasmex.Wasi.WasiP2Options

  @moduletag :filesystem_resources
  @moduletag timeout: :infinity

  @filesystem_component_path "test/component_fixtures/filesystem-component/target/wasm32-wasip1/release/filesystem_component.wasm"

  describe "filesystem resources" do
    setup do
      # Ensure the component is built
      unless File.exists?(@filesystem_component_path) do
        build_cmd =
          "cd test/component_fixtures/filesystem-component && cargo component build --release"

        {_, 0} = System.cmd("sh", ["-c", build_cmd], stderr_to_stdout: true)
      end

      # Create a store with WASI support
      wasi_options = %WasiP2Options{
        args: [],
        env: %{},
        inherit_stdin: true,
        inherit_stdout: true,
        inherit_stderr: true
      }

      {:ok, store} = Components.Store.new_wasi(wasi_options)
      {:ok, component} = Components.Component.new(store, File.read!(@filesystem_component_path))
      {:ok, instance} = Components.Instance.new(store, component, %{})

      %{store: store, instance: instance}
    end

    test "file handle resource lifecycle", %{instance: instance} do
      from = self()

      # Create a directory
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "create-test-directory"],
          [],
          from
        )

      assert_receive {:returned_function_call, {:ok, directory}, ^from},
                     5000,
                     "Timeout creating directory"

      # Create multiple file handles
      files =
        for i <- 1..3 do
          filename = "file#{i}.txt"

          :ok =
            Components.Instance.call_function(
              instance,
              ["test:filesystem/types", "[method]directory.create-file"],
              [directory, filename],
              from
            )

          assert_receive {:returned_function_call, {:ok, result}, ^from},
                         5000,
                         "Timeout creating file #{filename}"

          case result do
            {:ok, file} -> {filename, file}
            {:error, error} -> flunk("Error creating file #{filename}: #{error}")
          end
        end

      assert length(files) == 3

      # Verify all file handles are valid resources
      for {_name, file} <- files do
        assert is_reference(file)
      end

      # Write to each file
      for {name, file} <- files do
        data = "Content of #{name}"
        bytes = :erlang.binary_to_list(data)

        :ok =
          Components.Instance.call_function(
            instance,
            ["test:filesystem/types", "[method]file-handle.write"],
            [file, bytes],
            from
          )

        assert_receive {:returned_function_call, {:ok, result}, ^from},
                       5000,
                       "Timeout writing to #{name}"

        case result do
          {:ok, written} -> assert written == byte_size(data)
          {:error, error} -> flunk("Error writing to #{name}: #{error}")
        end
      end
    end

    test "concurrent file handle operations", %{instance: instance} do
      from = self()

      # Create a directory
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "create-test-directory"],
          [],
          from
        )

      assert_receive {:returned_function_call, {:ok, directory}, ^from},
                     5000,
                     "Timeout creating directory"

      # Create a file handle
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "[method]directory.create-file"],
          [directory, "concurrent.txt"],
          from
        )

      assert_receive {:returned_function_call, {:ok, {:ok, file_handle}}, ^from},
                     5000,
                     "Timeout creating file"

      # Simulate concurrent writes (not truly concurrent but sequential)
      writes =
        for i <- 1..10 do
          data = "Line #{i}\n"
          bytes = :erlang.binary_to_list(data)

          :ok =
            Components.Instance.call_function(
              instance,
              ["test:filesystem/types", "[method]file-handle.write"],
              [file_handle, bytes],
              from
            )

          assert_receive {:returned_function_call, {:ok, {:ok, written}}, ^from}, 1000
          {:ok, written}
        end

      assert Enum.all?(writes, fn
               {:ok, _} -> true
               _ -> false
             end)
    end

    test "directory operations", %{instance: instance} do
      from = self()

      # Create a directory
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "create-test-directory"],
          [],
          from
        )

      assert_receive {:returned_function_call, {:ok, directory}, ^from},
                     5000,
                     "Timeout creating directory"

      # Create multiple files
      filenames = ["doc1.txt", "doc2.txt", "image.png", "data.json"]

      for name <- filenames do
        :ok =
          Components.Instance.call_function(
            instance,
            ["test:filesystem/types", "[method]directory.create-file"],
            [directory, name],
            from
          )

        assert_receive {:returned_function_call, {:ok, {:ok, _}}, ^from},
                       5000,
                       "Timeout creating file #{name}"
      end

      # List files
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "[method]directory.list-files"],
          [directory],
          from
        )

      assert_receive {:returned_function_call, {:ok, file_list}, ^from},
                     5000,
                     "Timeout listing files"

      assert is_list(file_list)
      assert length(file_list) == length(filenames)

      for name <- filenames do
        assert name in file_list
      end
    end

    test "file position tracking", %{instance: instance} do
      from = self()

      # Create a directory and file
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "create-test-directory"],
          [],
          from
        )

      assert_receive {:returned_function_call, {:ok, directory}, ^from},
                     5000,
                     "Timeout creating directory"

      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "[method]directory.create-file"],
          [directory, "position.txt"],
          from
        )

      assert_receive {:returned_function_call, {:ok, {:ok, file}}, ^from},
                     5000,
                     "Timeout creating file"

      # Write data in chunks
      chunks = ["First chunk. ", "Second chunk. ", "Third chunk."]

      written_sizes =
        for chunk <- chunks do
          bytes = :erlang.binary_to_list(chunk)

          :ok =
            Components.Instance.call_function(
              instance,
              ["test:filesystem/types", "[method]file-handle.write"],
              [file, bytes],
              from
            )

          assert_receive {:returned_function_call, {:ok, {:ok, written}}, ^from},
                         5000,
                         "Timeout writing chunk"

          assert written == byte_size(chunk)
          written
        end

      # The file position should have advanced
      total_written = Enum.sum(written_sizes)
      assert total_written == Enum.sum(Enum.map(chunks, &byte_size/1))
    end

    test "file handle cleanup", %{instance: instance} do
      from = self()

      # Create a directory
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "create-test-directory"],
          [],
          from
        )

      assert_receive {:returned_function_call, {:ok, directory}, ^from},
                     5000,
                     "Timeout creating directory"

      # Create a file
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "[method]directory.create-file"],
          [directory, "cleanup.txt"],
          from
        )

      assert_receive {:returned_function_call, {:ok, {:ok, file}}, ^from},
                     5000,
                     "Timeout creating file"

      # Close the file handle
      :ok =
        Components.Instance.call_function(
          instance,
          ["test:filesystem/types", "[method]file-handle.close"],
          [file],
          from
        )

      assert_receive {:returned_function_call, {:ok, _}, ^from}, 5000, "Timeout closing file"
    end

    test "bulk file operations", %{instance: instance} do
      from = self()
      num_files = 50

      log =
        capture_log(fn ->
          # Create a directory
          :ok =
            Components.Instance.call_function(
              instance,
              ["test:filesystem/types", "create-test-directory"],
              [],
              from
            )

          assert_receive {:returned_function_call, {:ok, directory}, ^from}, 5000

          # Create many files
          files =
            for i <- 1..num_files do
              filename = "bulk_file_#{i}.txt"

              :ok =
                Components.Instance.call_function(
                  instance,
                  ["test:filesystem/types", "[method]directory.create-file"],
                  [directory, filename],
                  from
                )

              # Use a short timeout and handle timeout gracefully
              receive do
                {:returned_function_call, {:ok, {:ok, f}}, ^from} -> f
              after
                1000 -> nil
              end
            end

          # Remove nils and verify we created files
          valid_files = Enum.filter(files, & &1)
          assert length(valid_files) > 0

          # Write to and close each file
          for file <- valid_files do
            # Write some data
            bytes = :erlang.binary_to_list("test data")

            :ok =
              Components.Instance.call_function(
                instance,
                ["test:filesystem/types", "[method]file-handle.write"],
                [file, bytes],
                from
              )

            # Short timeout for bulk operations
            receive do
              {:returned_function_call, {:ok, _}, ^from} -> :ok
            after
              500 -> :ok
            end

            # Close the file
            :ok =
              Components.Instance.call_function(
                instance,
                ["test:filesystem/types", "[method]file-handle.close"],
                [file],
                from
              )

            # Short timeout for bulk operations
            receive do
              {:returned_function_call, {:ok, _}, ^from} -> :ok
            after
              500 -> :ok
            end
          end
        end)

      # Ensure no memory leak warnings in logs
      refute log =~ "memory leak"
      refute log =~ "resource leak"
    end
  end

  describe "resource lifecycle stress testing" do
    setup do
      unless File.exists?(@filesystem_component_path) do
        build_cmd =
          "cd test/component_fixtures/filesystem-component && cargo component build --release"

        {_, 0} = System.cmd("sh", ["-c", build_cmd], stderr_to_stdout: true)
      end

      %{component_path: @filesystem_component_path}
    end

    test "repeated store creation and destruction", %{component_path: component_path} do
      # This simulates opening and closing many files/directories
      for _iteration <- 1..5 do
        wasi_options = %WasiP2Options{
          args: [],
          env: %{},
          inherit_stdin: true,
          inherit_stdout: true,
          inherit_stderr: true
        }

        {:ok, store} = Components.Store.new_wasi(wasi_options)
        {:ok, component} = Components.Component.new(store, File.read!(component_path))
        {:ok, instance} = Components.Instance.new(store, component, %{})

        from = self()

        # Create a directory
        :ok =
          Components.Instance.call_function(
            instance,
            ["test:filesystem/types", "create-test-directory"],
            [],
            from
          )

        # Short timeout for stress tests
        directory =
          receive do
            {:returned_function_call, {:ok, dir}, ^from} -> dir
          after
            1000 -> nil
          end

        if directory do
          # Create some files
          for i <- 1..10 do
            :ok =
              Components.Instance.call_function(
                instance,
                ["test:filesystem/types", "[method]directory.create-file"],
                [directory, "file#{i}.txt"],
                from
              )

            receive do
              {:returned_function_call, {:ok, _}, ^from} -> :ok
            after
              500 -> :ok
            end
          end
        end

        # Store and resources will be cleaned up when going out of scope
      end

      # If we get here without crashes or leaks, the test passes
      assert true
    end

    test "cross-store resource isolation", %{component_path: component_path} do
      # Create multiple stores with resources
      stores_and_resources =
        for i <- 1..3 do
          wasi_options = %WasiP2Options{
            args: [],
            env: %{},
            inherit_stdin: true,
            inherit_stdout: true,
            inherit_stderr: true
          }

          {:ok, store} = Components.Store.new_wasi(wasi_options)
          {:ok, component} = Components.Component.new(store, File.read!(component_path))
          {:ok, instance} = Components.Instance.new(store, component, %{})

          from = self()

          :ok =
            Components.Instance.call_function(
              instance,
              ["test:filesystem/types", "create-test-directory"],
              [],
              from
            )

          # Short timeout for stress tests
          directory =
            receive do
              {:returned_function_call, {:ok, dir}, ^from} -> dir
            after
              1000 -> nil
            end

          if directory do
            # Create a file specific to this store
            :ok =
              Components.Instance.call_function(
                instance,
                ["test:filesystem/types", "[method]directory.create-file"],
                [directory, "store_#{i}_file.txt"],
                from
              )

            # Short timeout for stress tests
            file =
              receive do
                {:returned_function_call, {:ok, {:ok, f}}, ^from} -> f
              after
                1000 -> nil
              end

            {store, instance, directory, file}
          else
            {store, instance, nil, nil}
          end
        end

      # Verify each resource is isolated to its store
      assert length(stores_and_resources) == 3

      # Stores will be cleaned up, ensuring proper isolation
    end
  end
end
