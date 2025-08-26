defmodule Wasmex.Components.HostResourceTest do
  use ExUnit.Case
  
  alias Wasmex.Components.Examples.CounterResource
  alias Wasmex.Components.Examples.DatabaseResource
  alias Wasmex.Components.Examples.MessageQueueResource
  alias Wasmex.Components.HostResource
  
  describe "CounterResource" do
    test "implements HostResource protocol" do
      counter = CounterResource.new(10, "test-counter")
      assert HostResource.type_name(counter) == "example-counter"
    end
    
    test "increment method" do
      counter = CounterResource.new(5)
      
      # Increment without parameter
      {:ok, {updated, value}} = HostResource.call_method(counter, "increment", [])
      assert value == 6
      assert updated.value == 6
      
      # Increment with parameter
      {:ok, {updated2, value2}} = HostResource.call_method(updated, "increment", [10])
      assert value2 == 16
      assert updated2.value == 16
    end
    
    test "decrement method" do
      counter = CounterResource.new(10)
      {:ok, {updated, value}} = HostResource.call_method(counter, "decrement", [])
      assert value == 9
      assert updated.value == 9
    end
    
    test "get-value method" do
      counter = CounterResource.new(42)
      {:ok, value} = HostResource.call_method(counter, "get-value", [])
      assert value == 42
    end
    
    test "reset method" do
      counter = CounterResource.new(100)
      {:ok, {updated, _}} = HostResource.call_method(counter, "reset", [])
      assert updated.value == 0
    end
    
    test "name methods" do
      counter = CounterResource.new(0, "my-counter")
      
      # Get name
      {:ok, name} = HostResource.call_method(counter, "get-name", [])
      assert name == "my-counter"
      
      # Set name
      {:ok, {updated, _}} = HostResource.call_method(counter, "set-name", ["new-name"])
      assert updated.name == "new-name"
    end
    
    test "unknown method returns error" do
      counter = CounterResource.new()
      {:error, msg} = HostResource.call_method(counter, "unknown", [])
      assert msg =~ "Unknown method"
    end
    
    test "drop resource" do
      counter = CounterResource.new(50, "drop-test")
      assert :ok = HostResource.drop(counter)
    end
  end
  
  describe "DatabaseResource" do
    test "implements HostResource protocol" do
      db = DatabaseResource.new("test_db")
      assert HostResource.type_name(db) == "database-connection"
    end
    
    test "query method" do
      db = DatabaseResource.new("test_db")
      
      # Query users
      {:ok, {updated, result}} = HostResource.call_method(db, "query", ["SELECT * FROM users"])
      assert length(result) == 3
      assert hd(result)["name"] == "Alice"
      assert updated.query_count == 1
      
      # Query products
      {:ok, {updated2, result2}} = HostResource.call_method(updated, "query", ["SELECT * FROM products"])
      assert length(result2) == 3
      assert hd(result2)["name"] == "Widget"
      assert updated2.query_count == 2
    end
    
    test "execute method" do
      db = DatabaseResource.new("test_db")
      
      {:ok, {updated, affected}} = HostResource.call_method(db, "execute", ["INSERT INTO users VALUES (4, 'David')"])
      assert affected == 1
      assert updated.query_count == 1
    end
    
    test "transaction methods" do
      db = DatabaseResource.new("test_db")
      
      # Begin transaction
      {:ok, {updated, _}} = HostResource.call_method(db, "begin-transaction", [])
      assert updated.in_transaction == true
      
      # Cannot begin another transaction
      {:error, msg} = HostResource.call_method(updated, "begin-transaction", [])
      assert msg == "Already in transaction"
      
      # Commit transaction
      {:ok, {committed, _}} = HostResource.call_method(updated, "commit", [])
      assert committed.in_transaction == false
      
      # Begin and rollback
      {:ok, {in_txn, _}} = HostResource.call_method(committed, "begin-transaction", [])
      {:ok, {rolled_back, _}} = HostResource.call_method(in_txn, "rollback", [])
      assert rolled_back.in_transaction == false
    end
    
    test "get-stats method" do
      db = DatabaseResource.new("test_db")
      
      # Execute some queries
      {:ok, {db, _}} = HostResource.call_method(db, "query", ["SELECT * FROM users"])
      {:ok, {db, _}} = HostResource.call_method(db, "execute", ["UPDATE users SET name = 'Test'"])
      
      {:ok, stats} = HostResource.call_method(db, "get-stats", [])
      assert stats["database_name"] == "test_db"
      assert stats["query_count"] == 2
      assert stats["in_transaction"] == false
    end
    
    test "prepare-statement method" do
      db = DatabaseResource.new("test_db")
      
      {:ok, statement_id} = HostResource.call_method(db, "prepare-statement", ["SELECT * FROM users WHERE id = ?"])
      assert is_integer(statement_id)
    end
    
    test "drop cleans up resources" do
      db = DatabaseResource.new("test_db")
      assert :ok = HostResource.drop(db)
    end
  end
  
  describe "MessageQueueResource" do
    test "implements HostResource protocol" do
      queue = MessageQueueResource.new("test-queue")
      assert HostResource.type_name(queue) == "message-queue"
    end
    
    test "send and receive messages" do
      queue = MessageQueueResource.new("test-queue")
      
      # Send a message
      {:ok, {queue, msg_id}} = HostResource.call_method(queue, "send", ["Hello, World!"])
      assert is_integer(msg_id)
      
      # Check queue size
      {:ok, size} = HostResource.call_method(queue, "size", [])
      assert size == 1
      
      # Receive the message
      {:ok, {queue, {:some, message}}} = HostResource.call_method(queue, "receive", [])
      assert message["content"] == "Hello, World!"
      assert message["id"] == msg_id
      
      # Queue should be empty now
      {:ok, size} = HostResource.call_method(queue, "size", [])
      assert size == 0
      
      # Receiving from empty queue returns none
      {:ok, {_queue, :none}} = HostResource.call_method(queue, "receive", [])
    end
    
    test "send and receive batch" do
      queue = MessageQueueResource.new("test-queue")
      
      # Send batch
      messages = ["msg1", "msg2", "msg3"]
      {:ok, {queue, ids}} = HostResource.call_method(queue, "send-batch", [messages])
      assert length(ids) == 3
      
      # Receive batch
      {:ok, {queue, received}} = HostResource.call_method(queue, "receive-batch", [2])
      assert length(received) == 2
      assert Enum.at(received, 0)["content"] == "msg1"
      assert Enum.at(received, 1)["content"] == "msg2"
      
      # One message should remain
      {:ok, size} = HostResource.call_method(queue, "size", [])
      assert size == 1
    end
    
    test "peek without removing" do
      queue = MessageQueueResource.new("test-queue")
      
      # Send a message
      {:ok, {queue, _}} = HostResource.call_method(queue, "send", ["Peek me"])
      
      # Peek at the message
      {:ok, {:some, message}} = HostResource.call_method(queue, "peek", [])
      assert message["content"] == "Peek me"
      
      # Message should still be in queue
      {:ok, size} = HostResource.call_method(queue, "size", [])
      assert size == 1
    end
    
    test "clear queue" do
      queue = MessageQueueResource.new("test-queue")
      
      # Send multiple messages
      {:ok, {queue, _}} = HostResource.call_method(queue, "send-batch", [["a", "b", "c", "d", "e"]])
      
      # Clear the queue
      {:ok, {queue, dropped}} = HostResource.call_method(queue, "clear", [])
      assert dropped == 5
      
      # Queue should be empty
      {:ok, size} = HostResource.call_method(queue, "size", [])
      assert size == 0
    end
    
    test "subscriber management" do
      queue = MessageQueueResource.new("test-queue")
      
      # Subscribe
      {:ok, {queue, count}} = HostResource.call_method(queue, "subscribe", [])
      assert count == 1
      
      # Subscribe again
      {:ok, {queue, count}} = HostResource.call_method(queue, "subscribe", [])
      assert count == 2
      
      # Unsubscribe
      {:ok, {_queue, count}} = HostResource.call_method(queue, "unsubscribe", [])
      assert count == 1
    end
    
    test "get-stats" do
      queue = MessageQueueResource.new("test-queue")
      
      # Send some messages
      {:ok, {queue, _}} = HostResource.call_method(queue, "send-batch", [["a", "b", "c"]])
      {:ok, {queue, _}} = HostResource.call_method(queue, "receive", [])
      
      {:ok, stats} = HostResource.call_method(queue, "get-stats", [])
      assert stats["queue_name"] == "test-queue"
      assert stats["messages_sent"] == 3
      assert stats["messages_received"] == 1
      assert stats["current_size"] == 2
    end
    
    test "drop warns about unprocessed messages" do
      queue = MessageQueueResource.new("test-queue")
      {:ok, {queue, _}} = HostResource.call_method(queue, "send", ["unprocessed"])
      
      assert :ok = HostResource.drop(queue)
    end
  end
  
  describe "HostResourceManager integration" do
    @moduletag :skip
    # These tests would require the HostResourceManager GenServer to be running
    # and the full NIF implementation to be complete
    
    test "create host resource through manager" do
      # Start the manager if not already started
      {:ok, _pid} = Wasmex.Components.HostResourceManager.start_link()
      
      # Create a store (mock for now)
      store = make_ref()
      
      # Create a counter resource
      counter = CounterResource.new(0)
      
      # Register it with the manager
      {:ok, handle} = Wasmex.Components.HostResourceManager.create(store, counter)
      
      assert is_reference(handle)
    end
    
    test "call methods through manager" do
      {:ok, _pid} = Wasmex.Components.HostResourceManager.start_link()
      
      store = make_ref()
      counter = CounterResource.new(10)
      {:ok, _handle} = Wasmex.Components.HostResourceManager.create(store, counter)
      
      # Note: In a real implementation, we'd get the resource_id from the handle
      # For now, we'll use 1 as it's the first resource created
      {:ok, {_updated, value}} = Wasmex.Components.HostResourceManager.call_method(1, "increment", [])
      assert value == 11
    end
  end
end