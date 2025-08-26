defmodule Wasmex.Components.Examples.SupervisionPatterns do
  @moduledoc """
  Common supervision patterns for WASM component resources.

  These are examples showing how to integrate ResourceServer with standard OTP supervisors.
  Users should adapt these patterns to their specific needs.

  ## Pattern 1: Application-level Resources

      defmodule MyApp.Application do
        use Application
        
        def start(_type, _args) do
          children = [
            # Permanent database connection
            {Wasmex.Components.ResourceServer, 
             {MyApp.DatabaseResource, "production"},
             restart: :permanent},
             
            # Transient cache (restarts on crash)
            {Wasmex.Components.ResourceServer,
             {MyApp.CacheResource, %{ttl: 3600}},
             restart: :transient}
          ]
          
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  ## Pattern 2: Dynamic Resource Pool

      defmodule MyApp.ResourcePool do
        def start_link do
          DynamicSupervisor.start_link(
            strategy: :one_for_one,
            name: __MODULE__
          )
        end
        
        def add_resource(module, args) do
          spec = {Wasmex.Components.ResourceServer, {module, args}}
          DynamicSupervisor.start_child(__MODULE__, spec)
        end
      end

  ## Pattern 3: Per-Store Resources

      defmodule MyApp.StoreManager do
        use Supervisor
        
        def start_link(store_name) do
          Supervisor.start_link(__MODULE__, store_name, name: store_name)
        end
        
        def init(store_name) do
          children = [
            # Resources scoped to this store
            {Wasmex.Components.ResourceServer, 
             {MyApp.StoreResource, store_name}}
          ]
          
          Supervisor.init(children, strategy: :rest_for_one)
        end
      end

  ## Pattern 4: Resource with Health Monitoring

      defmodule MyApp.MonitoredResource do
        use GenServer
        
        def start_link(resource_args) do
          GenServer.start_link(__MODULE__, resource_args)
        end
        
        def init(args) do
          # Start the resource under a supervisor
          {:ok, pid} = Wasmex.Components.ResourceServer.start_link(
            MyApp.DatabaseResource, 
            args
          )
          
          # Monitor it
          Process.monitor(pid)
          
          # Schedule health checks
          :timer.send_interval(30_000, :health_check)
          
          {:ok, %{resource: pid, failures: 0}}
        end
        
        def handle_info(:health_check, state) do
          case check_health(state.resource) do
            :ok -> 
              {:noreply, %{state | failures: 0}}
            :error ->
              if state.failures >= 3 do
                # Restart after 3 failures
                Process.exit(state.resource, :unhealthy)
              end
              {:noreply, %{state | failures: state.failures + 1}}
          end
        end
      end

  ## Pattern 5: Linked Resource Pairs

      # When you need two resources that depend on each other
      defmodule MyApp.LinkedResources do
        use Supervisor
        
        def start_link(opts) do
          Supervisor.start_link(__MODULE__, opts)
        end
        
        def init(_opts) do
          children = [
            {Wasmex.Components.ResourceServer,
             {MyApp.ProducerResource, "input_queue"},
             id: :producer},
             
            {Wasmex.Components.ResourceServer,
             {MyApp.ConsumerResource, "output_queue"},
             id: :consumer}
          ]
          
          # If producer dies, restart both
          Supervisor.init(children, strategy: :one_for_all)
        end
      end

  ## Key Principles

  1. **Let OTP handle lifecycle** - Don't manually manage resource processes
  2. **Choose appropriate restart strategies** - Based on resource criticality
  3. **Use standard patterns** - DynamicSupervisor, Supervisor, GenServer
  4. **Keep it simple** - Resources are just GenServers, treat them as such
  """
end
