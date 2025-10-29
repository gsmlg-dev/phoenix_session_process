defmodule Phoenix.SessionProcess.PubSubBroadcastTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.SessionId

  @pubsub_name TestBroadcastPubSub

  # Test session process that uses broadcast_state_change
  defmodule TestBroadcastProcess do
    use Phoenix.SessionProcess, :process

    @impl true
    def init(init_arg) do
      {:ok, init_arg}
    end

    @impl true
    def handle_call(:get_state, _from, state) do
      {:reply, {:ok, state}, state}
    end

    @impl true
    def handle_call(:get_topic, _from, state) do
      topic = session_topic()
      {:reply, topic, state}
    end

    @impl true
    def handle_call({:update_state, new_state}, _from, _state) do
      # Use the helper from the macro - test default (no explicit pubsub)
      broadcast_state_change(new_state)
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call({:update_with_pubsub, new_state, pubsub}, _from, _state) do
      # Use the helper with explicit pubsub module
      broadcast_state_change(new_state, pubsub)
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_cast({:update_async, new_state}, _state) do
      # Broadcast in a cast
      broadcast_state_change(new_state)
      {:noreply, new_state}
    end
  end

  setup do
    # Start PubSub for this test
    case start_supervised({Phoenix.PubSub, name: @pubsub_name}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Generate unique session ID
    session_id = SessionId.generate_unique_session_id()

    # Start session process
    {:ok, _pid} =
      SessionProcess.start(session_id, TestBroadcastProcess, %{user: "test", count: 0})

    on_exit(fn ->
      if SessionProcess.started?(session_id) do
        SessionProcess.terminate(session_id)
      end
    end)

    %{session_id: session_id}
  end

  describe "broadcast_state_change/2 with explicit pubsub" do
    test "successfully broadcasts to PubSub topic", %{session_id: session_id} do
      # Subscribe to the topic
      topic = "session:#{session_id}:state"
      Phoenix.PubSub.subscribe(@pubsub_name, topic)

      # Update state with broadcast
      new_state = %{user: "updated", count: 42}
      result = SessionProcess.call(session_id, {:update_with_pubsub, new_state, @pubsub_name})

      assert result == :ok

      # Should receive the broadcast
      assert_receive {:session_state_change, ^new_state}, 100
    end

    test "returns state unchanged", %{session_id: session_id} do
      # Subscribe to the topic
      topic = "session:#{session_id}:state"
      Phoenix.PubSub.subscribe(@pubsub_name, topic)

      new_state = %{user: "test2", count: 99}
      SessionProcess.call(session_id, {:update_with_pubsub, new_state, @pubsub_name})

      # Verify state is set correctly
      {:ok, state} = SessionProcess.call(session_id, :get_state)
      assert state == new_state
    end

    test "broadcasts to multiple subscribers", %{session_id: session_id} do
      # Subscribe from current process
      topic = "session:#{session_id}:state"
      Phoenix.PubSub.subscribe(@pubsub_name, topic)

      # Subscribe from another process
      parent = self()

      subscriber =
        spawn(fn ->
          Phoenix.PubSub.subscribe(@pubsub_name, topic)
          send(parent, :subscribed)

          receive do
            {:session_state_change, state} -> send(parent, {:subscriber_received, state})
          after
            1000 -> send(parent, :subscriber_timeout)
          end
        end)

      assert_receive :subscribed, 100

      # Broadcast state change
      new_state = %{broadcast: "to all"}
      SessionProcess.call(session_id, {:update_with_pubsub, new_state, @pubsub_name})

      # Both should receive
      assert_receive {:session_state_change, ^new_state}, 100
      assert_receive {:subscriber_received, ^new_state}, 100

      # Clean up
      if Process.alive?(subscriber), do: Process.exit(subscriber, :kill)
    end
  end

  describe "broadcast_state_change/1 with config" do
    setup do
      # Set pubsub in application config
      original_pubsub = Application.get_env(:phoenix_session_process, :pubsub)
      Application.put_env(:phoenix_session_process, :pubsub, @pubsub_name)

      on_exit(fn ->
        if original_pubsub do
          Application.put_env(:phoenix_session_process, :pubsub, original_pubsub)
        else
          Application.delete_env(:phoenix_session_process, :pubsub)
        end
      end)

      :ok
    end

    test "uses config-based pubsub module", %{session_id: session_id} do
      # Subscribe to the topic
      topic = "session:#{session_id}:state"
      Phoenix.PubSub.subscribe(@pubsub_name, topic)

      # Update state without explicit pubsub (should use config)
      new_state = %{config: "based", count: 1}
      result = SessionProcess.call(session_id, {:update_state, new_state})

      assert result == :ok

      # Should receive the broadcast via config
      assert_receive {:session_state_change, ^new_state}, 100
    end

    test "works in handle_cast", %{session_id: session_id} do
      # Subscribe to the topic
      topic = "session:#{session_id}:state"
      Phoenix.PubSub.subscribe(@pubsub_name, topic)

      # Update via cast
      new_state = %{async: true, count: 5}
      SessionProcess.cast(session_id, {:update_async, new_state})

      # Should receive the broadcast
      assert_receive {:session_state_change, ^new_state}, 100
    end
  end

  describe "broadcast_state_change/1 without pubsub config" do
    setup do
      # Ensure no pubsub in config
      original_pubsub = Application.get_env(:phoenix_session_process, :pubsub)
      Application.delete_env(:phoenix_session_process, :pubsub)

      on_exit(fn ->
        if original_pubsub do
          Application.put_env(:phoenix_session_process, :pubsub, original_pubsub)
        end
      end)

      :ok
    end

    test "handles missing pubsub gracefully (no crash)", %{session_id: session_id} do
      # This should not crash even without pubsub configured
      new_state = %{no_pubsub: true}

      # Should not raise an error
      result = SessionProcess.call(session_id, {:update_state, new_state})
      assert result == :ok

      # Verify state is still updated
      {:ok, state} = SessionProcess.call(session_id, :get_state)
      assert state == new_state
    end

    test "returns state even when pubsub is nil", %{session_id: session_id} do
      new_state = %{user: "test", value: 123}
      SessionProcess.call(session_id, {:update_state, new_state})

      # State should be returned and set correctly
      {:ok, state} = SessionProcess.call(session_id, :get_state)
      assert state == new_state
    end
  end

  describe "session_topic/0" do
    test "returns correct topic for current session", %{session_id: session_id} do
      topic = SessionProcess.call(session_id, :get_topic)

      assert topic == "session:#{session_id}:state"
    end

    test "format is session:SESSION_ID:state", %{session_id: session_id} do
      topic = SessionProcess.call(session_id, :get_topic)

      # Verify format
      assert String.starts_with?(topic, "session:")
      assert String.ends_with?(topic, ":state")
      assert String.contains?(topic, session_id)

      # Verify exact format
      expected = "session:#{session_id}:state"
      assert topic == expected
    end

    test "different sessions have different topics" do
      session_id1 = SessionId.generate_unique_session_id()
      session_id2 = SessionId.generate_unique_session_id()

      {:ok, _} = SessionProcess.start(session_id1, TestBroadcastProcess, %{})
      {:ok, _} = SessionProcess.start(session_id2, TestBroadcastProcess, %{})

      topic1 = SessionProcess.call(session_id1, :get_topic)
      topic2 = SessionProcess.call(session_id2, :get_topic)

      assert topic1 != topic2
      assert topic1 == "session:#{session_id1}:state"
      assert topic2 == "session:#{session_id2}:state"

      # Cleanup
      SessionProcess.terminate(session_id1)
      SessionProcess.terminate(session_id2)
    end
  end

  describe "broadcast message format" do
    setup do
      # Set pubsub in config
      Application.put_env(:phoenix_session_process, :pubsub, @pubsub_name)

      on_exit(fn ->
        Application.delete_env(:phoenix_session_process, :pubsub)
      end)

      :ok
    end

    test "broadcasts as {:session_state_change, state} tuple", %{session_id: session_id} do
      topic = "session:#{session_id}:state"
      Phoenix.PubSub.subscribe(@pubsub_name, topic)

      new_state = %{key: "value", nested: %{data: [1, 2, 3]}}
      SessionProcess.call(session_id, {:update_state, new_state})

      # Should receive exactly this format
      assert_receive {:session_state_change, received_state}, 100
      assert received_state == new_state
    end

    test "preserves state structure in broadcast", %{session_id: session_id} do
      topic = "session:#{session_id}:state"
      Phoenix.PubSub.subscribe(@pubsub_name, topic)

      # Complex state with various types
      new_state = %{
        string: "hello",
        number: 42,
        list: [1, 2, 3],
        map: %{nested: true},
        atom: :test,
        nil: nil
      }

      SessionProcess.call(session_id, {:update_state, new_state})

      assert_receive {:session_state_change, received}, 100

      # Verify all fields are preserved
      assert received.string == "hello"
      assert received.number == 42
      assert received.list == [1, 2, 3]
      assert received.map == %{nested: true}
      assert received.atom == :test
      assert received.nil == nil
    end
  end
end
