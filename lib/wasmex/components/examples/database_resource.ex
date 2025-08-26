defmodule Wasmex.Components.Examples.DatabaseResource do
  @moduledoc """
  Example implementation of a host-defined database connection resource.
  
  This demonstrates how to create a database connection resource that can be
  passed to WASM components, allowing them to perform database operations
  through a controlled interface.
  
  Note: This is a mock implementation for demonstration purposes.
  In a real application, you would integrate with actual database libraries.
  """
  
  defstruct [:connection_id, :database_name, :query_count, :in_transaction, :mock_data]
  
  @doc """
  Creates a new database connection resource.
  """
  def new(database_name) do
    %__MODULE__{
      connection_id: :erlang.unique_integer([:positive]),
      database_name: database_name,
      query_count: 0,
      in_transaction: false,
      mock_data: %{
        "users" => [
          %{"id" => 1, "name" => "Alice", "email" => "alice@example.com"},
          %{"id" => 2, "name" => "Bob", "email" => "bob@example.com"},
          %{"id" => 3, "name" => "Charlie", "email" => "charlie@example.com"}
        ],
        "products" => [
          %{"id" => 1, "name" => "Widget", "price" => 9.99},
          %{"id" => 2, "name" => "Gadget", "price" => 19.99},
          %{"id" => 3, "name" => "Doohickey", "price" => 14.99}
        ]
      }
    }
  end
  
  defimpl Wasmex.Components.HostResource do
    require Logger
    
    def type_name(_resource), do: "database-connection"
    
    def call_method(resource, "query", [sql]) when is_binary(sql) do
      Logger.debug("Database query: #{sql}")
      
      # Increment query count
      updated = %{resource | query_count: resource.query_count + 1}
      
      # Simple mock query handling
      result = cond do
        String.contains?(sql, "SELECT * FROM users") ->
          Map.get(resource.mock_data, "users", [])
          
        String.contains?(sql, "SELECT * FROM products") ->
          Map.get(resource.mock_data, "products", [])
          
        String.contains?(sql, "SELECT COUNT(*)") ->
          [%{"count" => 3}]
          
        true ->
          []
      end
      
      {:ok, {updated, result}}
    end
    
    def call_method(resource, "execute", [sql]) when is_binary(sql) do
      Logger.debug("Database execute: #{sql}")
      
      # Increment query count
      updated = %{resource | query_count: resource.query_count + 1}
      
      # Mock execute handling (INSERT, UPDATE, DELETE)
      affected_rows = cond do
        String.contains?(sql, "INSERT") -> 1
        String.contains?(sql, "UPDATE") -> 2
        String.contains?(sql, "DELETE") -> 1
        true -> 0
      end
      
      {:ok, {updated, affected_rows}}
    end
    
    def call_method(resource, "begin-transaction", []) do
      if resource.in_transaction do
        {:error, "Already in transaction"}
      else
        Logger.debug("Beginning transaction on connection #{resource.connection_id}")
        updated = %{resource | in_transaction: true}
        {:ok, {updated, nil}}
      end
    end
    
    def call_method(resource, "commit", []) do
      if resource.in_transaction do
        Logger.debug("Committing transaction on connection #{resource.connection_id}")
        updated = %{resource | in_transaction: false}
        {:ok, {updated, nil}}
      else
        {:error, "Not in transaction"}
      end
    end
    
    def call_method(resource, "rollback", []) do
      if resource.in_transaction do
        Logger.debug("Rolling back transaction on connection #{resource.connection_id}")
        updated = %{resource | in_transaction: false}
        {:ok, {updated, nil}}
      else
        {:error, "Not in transaction"}
      end
    end
    
    def call_method(resource, "get-stats", []) do
      stats = %{
        "connection_id" => resource.connection_id,
        "database_name" => resource.database_name,
        "query_count" => resource.query_count,
        "in_transaction" => resource.in_transaction
      }
      {:ok, stats}
    end
    
    def call_method(_resource, "prepare-statement", [sql]) when is_binary(sql) do
      # Mock prepared statement - just return a statement ID
      statement_id = :erlang.unique_integer([:positive])
      Logger.debug("Prepared statement #{statement_id}: #{sql}")
      {:ok, statement_id}
    end
    
    def call_method(_resource, method, params) do
      {:error, "Unknown database method: #{method} with params: #{inspect(params)}"}
    end
    
    def drop(resource) do
      Logger.info("Closing database connection #{resource.connection_id} to #{resource.database_name}")
      Logger.info("Total queries executed: #{resource.query_count}")
      
      if resource.in_transaction do
        Logger.warning("Connection dropped while in transaction - implicit rollback")
      end
      
      :ok
    end
  end
end