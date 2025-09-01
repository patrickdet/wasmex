#!/usr/bin/env elixir

# Run with: elixir benchmark_tokio.exs
# Requires: mix escript.install hex benchee

Mix.install([
  {:wasmex, path: "."},
  {:benchee, "~> 1.3"}
])

defmodule WasmexBenchmark do
  @moduledoc """
  Benchmark script to compare concurrency and memory usage between
  main branch and Tokio-based implementation.
  """

  def run do
    # Compile a simple WAT module with various functions
    wat = """
    (module
      ;; Simple function that just returns a value
      (func $fast (export "fast") (result i32)
        i32.const 42
      )
      
      ;; CPU-intensive function (factorial)
      (func $factorial (export "factorial") (param $n i32) (result i32)
        (local $result i32)
        (local $i i32)
        i32.const 1
        local.set $result
        i32.const 1
        local.set $i
        
        (loop $loop
          local.get $i
          local.get $n
          i32.gt_u
          br_if 0
          
          local.get $result
          local.get $i
          i32.mul
          local.set $result
          
          local.get $i
          i32.const 1
          i32.add
          local.set $i
          
          br $loop
        )
        
        local.get $result
      )
      
      ;; Memory-intensive function
      (memory (export "memory") 1)
      
      (func $memory_write (export "memory_write") (param $size i32)
        (local $i i32)
        i32.const 0
        local.set $i
        
        (loop $loop
          local.get $i
          local.get $size
          i32.ge_u
          br_if 0
          
          local.get $i
          local.get $i
          i32.store8
          
          local.get $i
          i32.const 1
          i32.add
          local.set $i
          
          br $loop
        )
      )
      
      ;; Simulate slow function with nested loops
      (func $slow (export "slow") (param $n i32) (result i32)
        (local $sum i32)
        (local $i i32)
        (local $j i32)
        
        i32.const 0
        local.set $sum
        i32.const 0
        local.set $i
        
        (loop $outer
          local.get $i
          local.get $n
          i32.ge_u
          br_if 0
          
          i32.const 0
          local.set $j
          
          (loop $inner
            local.get $j
            local.get $n
            i32.ge_u
            br_if 0
            
            local.get $sum
            i32.const 1
            i32.add
            local.set $sum
            
            local.get $j
            i32.const 1
            i32.add
            local.set $j
            
            br $inner
          )
          
          local.get $i
          i32.const 1
          i32.add
          local.set $i
          
          br $outer
        )
        
        local.get $sum
      )
    )
    """

    # Start a Wasmex instance
    {:ok, pid} = Wasmex.start_link(%{bytes: wat})
    
    IO.puts("\n🚀 Wasmex Tokio vs Main Branch Benchmark\n")
    IO.puts("=" <> String.duplicate("=", 60))
    
    # Benchmark 1: Sequential vs Concurrent execution
    benchmark_concurrency(pid)
    
    # Benchmark 2: Memory usage under load
    benchmark_memory_usage(pid)
    
    # Benchmark 3: BEAM scheduler responsiveness
    benchmark_scheduler_responsiveness(pid)
    
    # Benchmark 4: Mixed workload
    benchmark_mixed_workload(pid)
    
    # Cleanup
    GenServer.stop(pid)
  end
  
  defp benchmark_concurrency(pid) do
    IO.puts("\n📊 Benchmark 1: Concurrency Performance")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "sequential_fast_calls" => fn ->
          for _ <- 1..100 do
            {:ok, [42]} = Wasmex.call_function(pid, :fast, [])
          end
        end,
        "concurrent_fast_calls" => fn ->
          1..100
          |> Task.async_stream(fn _ ->
            Wasmex.call_function(pid, :fast, [])
          end, max_concurrency: 50, timeout: 10_000)
          |> Enum.to_list()
        end,
        "sequential_slow_calls" => fn ->
          for _ <- 1..10 do
            {:ok, _} = Wasmex.call_function(pid, :slow, [100])
          end
        end,
        "concurrent_slow_calls" => fn ->
          1..10
          |> Task.async_stream(fn _ ->
            Wasmex.call_function(pid, :slow, [100])
          end, max_concurrency: 10, timeout: 10_000)
          |> Enum.to_list()
        end
      },
      time: 5,
      memory_time: 2,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    )
  end
  
  defp benchmark_memory_usage(pid) do
    IO.puts("\n📊 Benchmark 2: Memory Usage Under Load")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "memory_operations_sequential" => fn ->
          for i <- 1..50 do
            {:ok, _} = Wasmex.call_function(pid, :memory_write, [i * 100])
          end
        end,
        "memory_operations_concurrent" => fn ->
          1..50
          |> Task.async_stream(fn i ->
            Wasmex.call_function(pid, :memory_write, [i * 100])
          end, max_concurrency: 25, timeout: 10_000)
          |> Enum.to_list()
        end
      },
      time: 3,
      memory_time: 2,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    )
  end
  
  defp benchmark_scheduler_responsiveness(pid) do
    IO.puts("\n📊 Benchmark 3: BEAM Scheduler Responsiveness")
    IO.puts("-" <> String.duplicate("-", 40))
    IO.puts("Testing how responsive the BEAM stays during heavy WebAssembly load...")
    
    # Start a process that measures scheduler responsiveness
    test_pid = self()
    
    monitor_pid = spawn_link(fn ->
      Stream.repeatedly(fn ->
        start = System.monotonic_time(:microsecond)
        send(test_pid, {:ping, self()})
        receive do
          :pong -> System.monotonic_time(:microsecond) - start
        after
          1000 -> :timeout
        end
      end)
      |> Stream.take(100)
      |> Enum.to_list()
      |> then(fn latencies ->
        valid_latencies = Enum.filter(latencies, &is_integer/1)
        send(test_pid, {:latencies, valid_latencies})
      end)
    end)
    
    # Run heavy WebAssembly workload concurrently
    workload_task = Task.async(fn ->
      1..50
      |> Task.async_stream(fn _ ->
        Wasmex.call_function(pid, :slow, [200])
      end, max_concurrency: 25, timeout: 30_000)
      |> Enum.to_list()
    end)
    
    # Handle pings while workload is running
    ping_handler = Task.async(fn ->
      Stream.repeatedly(fn ->
        receive do
          {:ping, from} -> send(from, :pong)
        after
          10 -> nil
        end
      end)
      |> Stream.take_while(fn _ -> 
        not Task.yield(workload_task, 0)
      end)
      |> Enum.to_list()
    end)
    
    # Wait for results
    Task.await(workload_task, 30_000)
    Task.await(ping_handler, 5_000)
    
    receive do
      {:latencies, latencies} ->
        if length(latencies) > 0 do
          avg = Enum.sum(latencies) / length(latencies)
          max = Enum.max(latencies)
          min = Enum.min(latencies)
          p99 = percentile(latencies, 99)
          
          IO.puts("  Scheduler latency during heavy load:")
          IO.puts("    Average: #{Float.round(avg / 1000, 2)}ms")
          IO.puts("    Min: #{Float.round(min / 1000, 2)}ms")
          IO.puts("    Max: #{Float.round(max / 1000, 2)}ms")
          IO.puts("    P99: #{Float.round(p99 / 1000, 2)}ms")
        else
          IO.puts("  No latency measurements collected")
        end
    after
      5000 -> IO.puts("  Timeout waiting for latency measurements")
    end
  end
  
  defp benchmark_mixed_workload(pid) do
    IO.puts("\n📊 Benchmark 4: Mixed Workload Performance")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "mixed_sequential" => fn ->
          for i <- 1..30 do
            case rem(i, 3) do
              0 -> Wasmex.call_function(pid, :fast, [])
              1 -> Wasmex.call_function(pid, :factorial, [10])
              2 -> Wasmex.call_function(pid, :memory_write, [500])
            end
          end
        end,
        "mixed_concurrent" => fn ->
          1..30
          |> Task.async_stream(fn i ->
            case rem(i, 3) do
              0 -> Wasmex.call_function(pid, :fast, [])
              1 -> Wasmex.call_function(pid, :factorial, [10])
              2 -> Wasmex.call_function(pid, :memory_write, [500])
            end
          end, max_concurrency: 15, timeout: 10_000)
          |> Enum.to_list()
        end,
        "mixed_high_concurrency" => fn ->
          1..100
          |> Task.async_stream(fn i ->
            case rem(i, 3) do
              0 -> Wasmex.call_function(pid, :fast, [])
              1 -> Wasmex.call_function(pid, :factorial, [5])
              2 -> Wasmex.call_function(pid, :memory_write, [100])
            end
          end, max_concurrency: 50, timeout: 10_000)
          |> Enum.to_list()
        end
      },
      time: 5,
      memory_time: 2,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    )
  end
  
  defp percentile(list, p) do
    sorted = Enum.sort(list)
    k = (length(sorted) - 1) * p / 100
    f = :erlang.floor(k)
    c = :erlang.ceil(k)
    
    if f == c do
      Enum.at(sorted, trunc(k))
    else
      d0 = Enum.at(sorted, trunc(f)) * (c - k)
      d1 = Enum.at(sorted, trunc(c)) * (k - f)
      trunc(d0 + d1)
    end
  end
end

# Run the benchmark
WasmexBenchmark.run()