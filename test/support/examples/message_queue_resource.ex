defmodule Wasmex.Test.Support.Examples.MessageQueueResource do
  @moduledoc """
  Example implementation of a message queue resource.

  This demonstrates how a message queue naturally fits the process model,
  with built-in concurrency, mailbox management, and automatic cleanup.

  ## Perfect Fit for Process Model

  Message queues are an ideal use case for resources:
  - Erlang processes already have mailboxes
  - Natural async message handling
  - Built-in timeout support
  - Process monitoring for consumer tracking
  - Automatic cleanup of unprocessed messages

  ## Usage

      # Start the queue resource
      {:ok, pid} = ResourceServer.start_link(
        MessageQueueResource,
        %{name: "events", max_size: 1000}
      )
      
      # Send messages
      {:ok, _} = ResourceServer.call_method(pid, "send", ["Hello, World!"])
      
      # Receive messages
      {:ok, message} = ResourceServer.call_method(pid, "receive", [])
      
      # Batch operations
      {:ok, messages} = ResourceServer.call_method(pid, "receive-batch", [10])
      
      # Queue automatically cleans up on termination
  """

  @behaviour Wasmex.Components.ResourceBehaviour

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :messages,
      :max_size,
      :total_sent,
      :total_received,
      :subscribers,
      :dead_letter_queue,
      :created_at,
      :last_activity
    ]
  end

  # ResourceBehaviour callbacks

  @impl true
  def type_name, do: "message-queue"

  @impl true
  def init(args) when is_map(args) do
    name = Map.get(args, :name, "default")
    max_size = Map.get(args, :max_size, 10_000)

    Logger.info("Initializing message queue: #{name} (max size: #{max_size})")

    state = %State{
      name: name,
      messages: :queue.new(),
      max_size: max_size,
      total_sent: 0,
      total_received: 0,
      subscribers: [],
      dead_letter_queue: :queue.new(),
      created_at: System.monotonic_time(:millisecond),
      last_activity: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  def init(name) when is_binary(name) do
    init(%{name: name})
  end

  def init(_), do: init(%{})

  @impl true
  def handle_method("send", [message], state) do
    current_size = :queue.len(state.messages)

    if current_size >= state.max_size do
      {:error, "Queue is full (#{current_size}/#{state.max_size})", state}
    else
      new_messages = :queue.in({message, System.monotonic_time(:millisecond)}, state.messages)

      new_state = %State{
        state
        | messages: new_messages,
          total_sent: state.total_sent + 1,
          last_activity: System.monotonic_time(:millisecond)
      }

      # Notify subscribers (in a real implementation)
      notify_subscribers(state.subscribers, {:new_message, message})

      {:reply, :ok, new_state}
    end
  end

  def handle_method("receive", [], state) do
    case :queue.out(state.messages) do
      {{:value, {message, _timestamp}}, new_queue} ->
        new_state = %State{
          state
          | messages: new_queue,
            total_received: state.total_received + 1,
            last_activity: System.monotonic_time(:millisecond)
        }

        {:reply, {:some, message}, new_state}

      {:empty, _} ->
        {:reply, :none, state}
    end
  end

  def handle_method("receive-batch", [max_count], state) when is_integer(max_count) do
    {messages, new_queue} = extract_messages(state.messages, max_count, [])

    new_state = %State{
      state
      | messages: new_queue,
        total_received: state.total_received + length(messages),
        last_activity: System.monotonic_time(:millisecond)
    }

    {:reply, messages, new_state}
  end

  def handle_method("peek", [], state) do
    case :queue.peek(state.messages) do
      {:value, {message, _timestamp}} ->
        {:reply, {:some, message}, state}

      :empty ->
        {:reply, :none, state}
    end
  end

  def handle_method("size", [], state) do
    {:reply, :queue.len(state.messages), state}
  end

  def handle_method("is-empty", [], state) do
    {:reply, :queue.is_empty(state.messages), state}
  end

  def handle_method("clear", [], state) do
    cleared_count = :queue.len(state.messages)

    new_state = %State{
      state
      | messages: :queue.new(),
        last_activity: System.monotonic_time(:millisecond)
    }

    Logger.debug("Cleared #{cleared_count} messages from queue #{state.name}")
    {:reply, cleared_count, new_state}
  end

  def handle_method("subscribe", [subscriber_id], state) do
    if subscriber_id in state.subscribers do
      {:reply, :already_subscribed, state}
    else
      new_state = %State{
        state
        | subscribers: [subscriber_id | state.subscribers]
      }

      Logger.debug("Subscriber #{subscriber_id} added to queue #{state.name}")
      {:reply, :ok, new_state}
    end
  end

  def handle_method("unsubscribe", [subscriber_id], state) do
    new_state = %State{
      state
      | subscribers: List.delete(state.subscribers, subscriber_id)
    }

    {:reply, :ok, new_state}
  end

  def handle_method("send-to-dlq", [message], state) do
    # Send message to dead letter queue
    new_dlq =
      :queue.in({message, System.monotonic_time(:millisecond), :manual}, state.dead_letter_queue)

    new_state = %State{
      state
      | dead_letter_queue: new_dlq,
        last_activity: System.monotonic_time(:millisecond)
    }

    {:reply, :ok, new_state}
  end

  def handle_method("dlq-size", [], state) do
    {:reply, :queue.len(state.dead_letter_queue), state}
  end

  def handle_method("get-stats", [], state) do
    uptime = System.monotonic_time(:millisecond) - state.created_at
    idle_time = System.monotonic_time(:millisecond) - state.last_activity

    stats = %{
      name: state.name,
      current_size: :queue.len(state.messages),
      max_size: state.max_size,
      total_sent: state.total_sent,
      total_received: state.total_received,
      subscriber_count: length(state.subscribers),
      dlq_size: :queue.len(state.dead_letter_queue),
      uptime_ms: uptime,
      idle_ms: idle_time,
      throughput_per_sec: calculate_throughput(state.total_sent + state.total_received, uptime)
    }

    {:reply, stats, state}
  end

  def handle_method("set-max-size", [new_max], state) when is_integer(new_max) and new_max > 0 do
    new_state = %State{state | max_size: new_max}
    {:reply, :ok, new_state}
  end

  def handle_method("process-with-timeout", [timeout_ms], state) when is_integer(timeout_ms) do
    # Simulate processing with timeout
    case :queue.out(state.messages) do
      {{:value, {message, timestamp}}, new_queue} ->
        age_ms = System.monotonic_time(:millisecond) - timestamp

        if age_ms > timeout_ms do
          # Message expired, move to DLQ
          new_dlq = :queue.in({message, timestamp, :timeout}, state.dead_letter_queue)

          new_state = %State{
            state
            | messages: new_queue,
              dead_letter_queue: new_dlq,
              last_activity: System.monotonic_time(:millisecond)
          }

          {:reply, {:expired, message}, new_state}
        else
          # Message still valid
          new_state = %State{
            state
            | messages: new_queue,
              total_received: state.total_received + 1,
              last_activity: System.monotonic_time(:millisecond)
          }

          {:reply, {:ok, message}, new_state}
        end

      {:empty, _} ->
        {:reply, :empty, state}
    end
  end

  def handle_method(method, params, state) do
    Logger.warning("Unknown queue method: #{method} with params: #{inspect(params)}")
    {:error, "Unknown method: #{method}", state}
  end

  @impl true
  def terminate(reason, state) do
    messages_lost = :queue.len(state.messages)
    dlq_size = :queue.len(state.dead_letter_queue)

    Logger.info(
      "Closing message queue: #{state.name}, " <>
        "messages lost: #{messages_lost}, " <>
        "DLQ size: #{dlq_size}, " <>
        "total processed: #{state.total_sent}/#{state.total_received}, " <>
        "reason: #{inspect(reason)}"
    )

    if messages_lost > 0 do
      Logger.warning("Queue #{state.name} terminated with #{messages_lost} unprocessed messages")
    end

    :ok
  end

  # Helper functions

  defp extract_messages(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp extract_messages(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, {message, _timestamp}}, new_queue} ->
        extract_messages(new_queue, count - 1, [message | acc])

      {:empty, _} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp notify_subscribers([], _event), do: :ok

  defp notify_subscribers(subscribers, event) do
    # In a real implementation, this would send notifications
    Logger.debug("Notifying #{length(subscribers)} subscribers of #{inspect(event)}")
    :ok
  end

  defp calculate_throughput(_total, uptime_ms) when uptime_ms == 0, do: 0

  defp calculate_throughput(total, uptime_ms) do
    Float.round(total / (uptime_ms / 1000), 2)
  end
end
