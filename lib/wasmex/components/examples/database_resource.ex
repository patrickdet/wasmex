defmodule Wasmex.Components.Examples.DatabaseResource do
  @moduledoc """
  Example implementation of a database connection resource.

  This demonstrates a more complex stateful resource that simulates database
  operations, running as a process with automatic cleanup.

  ## Key Benefits

  - Connection pooling naturally fits process model
  - Transactions are naturally scoped to process state
  - Connection failures isolate to single process
  - Automatic cleanup on process termination
  - Can implement timeouts and health checks

  ## Usage

      # Start the database resource
      {:ok, pid} = ResourceServer.start_link(
        DatabaseResource,
        "production_db"
      )
      
      # Execute queries
      {:ok, results} = ResourceServer.call_method(pid, "query", ["SELECT * FROM users"])
      
      # Manage transactions
      {:ok, _} = ResourceServer.call_method(pid, "begin-transaction", [])
      {:ok, _} = ResourceServer.call_method(pid, "execute", ["INSERT INTO users VALUES (...)"])
      {:ok, _} = ResourceServer.call_method(pid, "commit", [])
      
      # Connection automatically closes on process termination
  """

  @behaviour Wasmex.Components.ResourceBehaviour

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :database_name,
      :query_count,
      :in_transaction,
      :transaction_depth,
      :prepared_statements,
      :connection_start_time,
      :last_query_time
    ]
  end

  # Mock data for simulating database
  @users [
    %{"id" => 1, "name" => "Alice", "email" => "alice@example.com"},
    %{"id" => 2, "name" => "Bob", "email" => "bob@example.com"},
    %{"id" => 3, "name" => "Charlie", "email" => "charlie@example.com"}
  ]

  @products [
    %{"id" => 1, "name" => "Widget", "price" => 19.99},
    %{"id" => 2, "name" => "Gadget", "price" => 29.99},
    %{"id" => 3, "name" => "Doohickey", "price" => 39.99}
  ]

  # ResourceBehaviour callbacks

  @impl true
  def type_name, do: "database-connection"

  @impl true
  def init(database_name) when is_binary(database_name) do
    Logger.info("Connecting to database: #{database_name}")

    # Simulate connection establishment
    :timer.sleep(10)

    state = %State{
      database_name: database_name,
      query_count: 0,
      in_transaction: false,
      transaction_depth: 0,
      prepared_statements: %{},
      connection_start_time: System.monotonic_time(:millisecond),
      last_query_time: nil
    }

    Logger.info("Database connection established: #{database_name}")
    {:ok, state}
  end

  def init(_), do: {:error, "Database name must be a string"}

  @impl true
  def handle_method("query", [sql], state) do
    Logger.debug("Executing query: #{sql}")

    # Simulate query execution
    result = execute_mock_query(sql)

    new_state = %State{
      state
      | query_count: state.query_count + 1,
        last_query_time: System.monotonic_time(:millisecond)
    }

    {:reply, result, new_state}
  end

  def handle_method("execute", [sql], state) do
    Logger.debug("Executing statement: #{sql}")

    # Simulate statement execution
    affected_rows = simulate_execute(sql)

    new_state = %State{
      state
      | query_count: state.query_count + 1,
        last_query_time: System.monotonic_time(:millisecond)
    }

    {:reply, affected_rows, new_state}
  end

  def handle_method("begin-transaction", [], %State{in_transaction: true} = state) do
    # Nested transaction (savepoint)
    new_state = %State{state | transaction_depth: state.transaction_depth + 1}
    Logger.debug("Creating savepoint at depth #{new_state.transaction_depth}")
    {:reply, :ok, new_state}
  end

  def handle_method("begin-transaction", [], state) do
    Logger.debug("Beginning transaction")
    new_state = %State{state | in_transaction: true, transaction_depth: 0}
    {:reply, :ok, new_state}
  end

  def handle_method("commit", [], %State{in_transaction: false} = state) do
    {:error, "Not in transaction", state}
  end

  def handle_method("commit", [], %State{transaction_depth: depth} = state) when depth > 0 do
    # Release savepoint
    new_state = %State{state | transaction_depth: depth - 1}
    Logger.debug("Releasing savepoint at depth #{depth}")
    {:reply, :ok, new_state}
  end

  def handle_method("commit", [], state) do
    Logger.debug("Committing transaction")
    new_state = %State{state | in_transaction: false, transaction_depth: 0}
    {:reply, :ok, new_state}
  end

  def handle_method("rollback", [], %State{in_transaction: false} = state) do
    {:error, "Not in transaction", state}
  end

  def handle_method("rollback", [], %State{transaction_depth: depth} = state) when depth > 0 do
    # Rollback to savepoint
    new_state = %State{state | transaction_depth: depth - 1}
    Logger.debug("Rolling back to savepoint at depth #{depth}")
    {:reply, :ok, new_state}
  end

  def handle_method("rollback", [], state) do
    Logger.debug("Rolling back transaction")
    new_state = %State{state | in_transaction: false, transaction_depth: 0}
    {:reply, :ok, new_state}
  end

  def handle_method("prepare-statement", [sql], state) do
    statement_id = :erlang.phash2({sql, System.monotonic_time()})

    new_statements = Map.put(state.prepared_statements, statement_id, sql)
    new_state = %State{state | prepared_statements: new_statements}

    Logger.debug("Prepared statement #{statement_id}: #{sql}")
    {:reply, statement_id, new_state}
  end

  def handle_method("execute-prepared", [statement_id | params], state) do
    case Map.get(state.prepared_statements, statement_id) do
      nil ->
        {:error, "Statement not found: #{statement_id}", state}

      sql ->
        Logger.debug(
          "Executing prepared statement #{statement_id} with params: #{inspect(params)}"
        )

        # Simulate execution
        result = execute_mock_query(sql)

        new_state = %State{
          state
          | query_count: state.query_count + 1,
            last_query_time: System.monotonic_time(:millisecond)
        }

        {:reply, result, new_state}
    end
  end

  def handle_method("get-stats", [], state) do
    uptime = System.monotonic_time(:millisecond) - state.connection_start_time

    stats = %{
      database_name: state.database_name,
      query_count: state.query_count,
      in_transaction: state.in_transaction,
      transaction_depth: state.transaction_depth,
      prepared_statement_count: map_size(state.prepared_statements),
      uptime_ms: uptime,
      last_query_ms_ago:
        if state.last_query_time do
          System.monotonic_time(:millisecond) - state.last_query_time
        else
          nil
        end
    }

    {:reply, stats, state}
  end

  def handle_method("ping", [], state) do
    # Health check
    {:reply, :pong, state}
  end

  def handle_method("is-connected", [], state) do
    # Check connection status
    {:reply, true, state}
  end

  def handle_method(method, params, state) do
    Logger.warning("Unknown database method: #{method} with params: #{inspect(params)}")
    {:error, "Unknown method: #{method}", state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "Closing database connection: #{state.database_name}, " <>
        "total queries: #{state.query_count}, " <>
        "reason: #{inspect(reason)}"
    )

    # Rollback any open transactions
    if state.in_transaction do
      Logger.warning("Rolling back uncommitted transaction on connection close")
    end

    # Close prepared statements
    if map_size(state.prepared_statements) > 0 do
      Logger.debug("Closing #{map_size(state.prepared_statements)} prepared statements")
    end

    # Simulate connection cleanup
    :timer.sleep(5)

    :ok
  end

  # Helper functions

  defp execute_mock_query(sql) do
    sql_lower = String.downcase(sql)

    cond do
      String.contains?(sql_lower, "from users") ->
        @users

      String.contains?(sql_lower, "from products") ->
        @products

      String.contains?(sql_lower, "count(*)") ->
        [%{"count" => 3}]

      true ->
        []
    end
  end

  defp simulate_execute(sql) do
    sql_lower = String.downcase(sql)

    cond do
      String.starts_with?(sql_lower, "insert") -> 1
      String.starts_with?(sql_lower, "update") -> :rand.uniform(5)
      String.starts_with?(sql_lower, "delete") -> :rand.uniform(3)
      true -> 0
    end
  end
end
