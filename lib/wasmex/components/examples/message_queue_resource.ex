defmodule Wasmex.Components.Examples.MessageQueueResource do
  @moduledoc """
  Example implementation of a host-defined message queue resource.
  
  This demonstrates how to create a message queue resource that WASM components
  can use to send and receive messages, enabling async communication patterns.
  
  Note: This is a mock implementation using an in-memory queue.
  In production, you would integrate with actual message queue systems like
  RabbitMQ, Kafka, or AWS SQS.
  """
  
  defstruct [:queue_name, :messages, :subscriber_count, :stats]
  
  @doc """
  Creates a new message queue resource.
  """
  def new(queue_name) do
    %__MODULE__{
      queue_name: queue_name,
      messages: :queue.new(),
      subscriber_count: 0,
      stats: %{
        messages_sent: 0,
        messages_received: 0,
        messages_dropped: 0
      }
    }
  end
  
  defimpl Wasmex.Components.HostResource do
    require Logger
    
    def type_name(_resource), do: "message-queue"
    
    def call_method(resource, "send", [message]) when is_binary(message) do
      Logger.debug("Sending message to queue #{resource.queue_name}: #{String.slice(message, 0, 50)}...")
      
      # Add message to queue with timestamp
      timestamp = System.system_time(:millisecond)
      message_data = %{
        "content" => message,
        "timestamp" => timestamp,
        "id" => :erlang.unique_integer([:positive])
      }
      
      new_queue = :queue.in(message_data, resource.messages)
      
      # Update stats
      new_stats = Map.update!(resource.stats, :messages_sent, &(&1 + 1))
      
      updated = %{resource | messages: new_queue, stats: new_stats}
      {:ok, {updated, message_data["id"]}}
    end
    
    def call_method(resource, "send-batch", [messages]) when is_list(messages) do
      Logger.debug("Sending batch of #{length(messages)} messages to queue #{resource.queue_name}")
      
      timestamp = System.system_time(:millisecond)
      
      {new_queue, ids} = Enum.reduce(messages, {resource.messages, []}, fn msg, {q, ids} ->
        message_data = %{
          "content" => msg,
          "timestamp" => timestamp,
          "id" => :erlang.unique_integer([:positive])
        }
        {
          :queue.in(message_data, q),
          [message_data["id"] | ids]
        }
      end)
      
      # Update stats
      new_stats = Map.update!(resource.stats, :messages_sent, &(&1 + length(messages)))
      
      updated = %{resource | messages: new_queue, stats: new_stats}
      {:ok, {updated, Enum.reverse(ids)}}
    end
    
    def call_method(resource, "receive", []) do
      case :queue.out(resource.messages) do
        {{:value, message}, new_queue} ->
          Logger.debug("Received message from queue #{resource.queue_name}: id=#{message["id"]}")
          
          # Update stats
          new_stats = Map.update!(resource.stats, :messages_received, &(&1 + 1))
          
          updated = %{resource | messages: new_queue, stats: new_stats}
          {:ok, {updated, {:some, message}}}
          
        {:empty, _} ->
          {:ok, {resource, :none}}
      end
    end
    
    def call_method(resource, "receive-batch", [max_messages]) when is_integer(max_messages) do
      {messages, new_queue} = extract_messages(resource.messages, max_messages, [])
      
      if length(messages) > 0 do
        Logger.debug("Received batch of #{length(messages)} messages from queue #{resource.queue_name}")
        
        # Update stats
        new_stats = Map.update!(resource.stats, :messages_received, &(&1 + length(messages)))
        
        updated = %{resource | messages: new_queue, stats: new_stats}
        {:ok, {updated, messages}}
      else
        {:ok, {resource, []}}
      end
    end
    
    def call_method(resource, "peek", []) do
      case :queue.peek(resource.messages) do
        {:value, message} ->
          {:ok, {:some, message}}
        :empty ->
          {:ok, :none}
      end
    end
    
    def call_method(resource, "size", []) do
      size = :queue.len(resource.messages)
      {:ok, size}
    end
    
    def call_method(resource, "clear", []) do
      dropped_count = :queue.len(resource.messages)
      
      # Update stats
      new_stats = Map.update!(resource.stats, :messages_dropped, &(&1 + dropped_count))
      
      updated = %{resource | messages: :queue.new(), stats: new_stats}
      
      Logger.debug("Cleared #{dropped_count} messages from queue #{resource.queue_name}")
      
      {:ok, {updated, dropped_count}}
    end
    
    def call_method(resource, "subscribe", []) do
      updated = %{resource | subscriber_count: resource.subscriber_count + 1}
      
      Logger.debug("New subscriber to queue #{resource.queue_name}. Total: #{updated.subscriber_count}")
      
      {:ok, {updated, updated.subscriber_count}}
    end
    
    def call_method(resource, "unsubscribe", []) do
      new_count = max(0, resource.subscriber_count - 1)
      updated = %{resource | subscriber_count: new_count}
      
      Logger.debug("Unsubscribed from queue #{resource.queue_name}. Remaining: #{new_count}")
      
      {:ok, {updated, new_count}}
    end
    
    def call_method(resource, "get-stats", []) do
      # Convert atom keys to string keys
      stats = %{
        "messages_sent" => resource.stats.messages_sent,
        "messages_received" => resource.stats.messages_received,
        "messages_dropped" => resource.stats.messages_dropped,
        "queue_name" => resource.queue_name,
        "current_size" => :queue.len(resource.messages),
        "subscriber_count" => resource.subscriber_count
      }
      {:ok, stats}
    end
    
    def call_method(_resource, method, params) do
      {:error, "Unknown message queue method: #{method} with params: #{inspect(params)}"}
    end
    
    def drop(resource) do
      remaining = :queue.len(resource.messages)
      
      if remaining > 0 do
        Logger.warning("Dropping message queue #{resource.queue_name} with #{remaining} unprocessed messages")
      else
        Logger.info("Dropping empty message queue #{resource.queue_name}")
      end
      
      Logger.info("Queue stats - Sent: #{resource.stats.messages_sent}, Received: #{resource.stats.messages_received}, Dropped: #{resource.stats.messages_dropped + remaining}")
      
      :ok
    end
    
    # Helper function to extract multiple messages from queue
    defp extract_messages(queue, 0, acc), do: {Enum.reverse(acc), queue}
    defp extract_messages(queue, remaining, acc) do
      case :queue.out(queue) do
        {{:value, message}, new_queue} ->
          extract_messages(new_queue, remaining - 1, [message | acc])
        {:empty, _} ->
          {Enum.reverse(acc), queue}
      end
    end
  end
end