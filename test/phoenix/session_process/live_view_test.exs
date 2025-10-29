defmodule Phoenix.SessionProcess.LiveViewTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.LiveView, as: SessionLV
  alias Phoenix.SessionProcess.SessionId

  @pubsub_name TestLiveViewPubSub

  # Test process that uses Redux-only state management
  defmodule TestReduxProcess do
    use Phoenix.SessionProcess, :process
    alias Phoenix.SessionProcess.Redux

    @impl true
    def init(init_arg) do
      session_id = get_session_id()

      redux =
        Redux.init_state(
          init_arg,
          pubsub: TestLiveViewPubSub,
          pubsub_topic: "session:#{session_id}:redux"
        )

      {:ok, %{redux: redux}}
    end

    @impl true
    def handle_call(:get_redux_state, _from, state) do
      {:reply, {:ok, state.redux}, state}
    end

    @impl true
    def handle_call(:get_state, _from, state) do
      # For backward compatibility with some tests
      {:reply, {:ok, Redux.get_state(state.redux)}, state}
    end

    @impl true
    def handle_call(:get_custom_state, _from, state) do
      {:reply, {:ok, state.redux}, state}
    end

    @impl true
    def handle_call({:dispatch, action}, _from, state) do
      new_redux = Redux.dispatch(state.redux, action, &reducer/2)
      {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
    end

    @impl true
    def handle_cast({:dispatch_async, action}, state) do
      new_redux = Redux.dispatch(state.redux, action, &reducer/2)
      {:noreply, %{state | redux: new_redux}}
    end

    defp reducer(state, action) do
      case action do
        {:put, key, value} -> Map.put(state, key, value)
        {:set_user, user} -> %{state | user: user}
        {:increment} -> %{state | count: state.count + 1}
        _ -> state
      end
    end
  end

  setup do
    # Start PubSub for this test if not already started
    case start_supervised({Phoenix.PubSub, name: @pubsub_name}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Generate unique session ID for this test
    session_id = SessionId.generate_unique_session_id()

    # Start session process with TestReduxProcess
    {:ok, _pid} = SessionProcess.start(session_id, TestReduxProcess, %{user: "test", count: 0})

    on_exit(fn ->
      # Clean up session if it exists
      if SessionProcess.started?(session_id) do
        SessionProcess.terminate(session_id)
      end
    end)

    %{session_id: session_id}
  end

  describe "mount_session/3" do
    test "successfully mounts with valid session_id", %{session_id: session_id} do
      socket = %{assigns: %{}}

      result = SessionLV.mount_session(socket, session_id, @pubsub_name)

      assert {:ok, updated_socket, initial_state} = result
      assert is_map(initial_state)
      assert initial_state.user == "test"
      assert initial_state.count == 0
      assert updated_socket.assigns.__session_id__ == session_id
      assert updated_socket.assigns.__session_pubsub__ == @pubsub_name
    end

    test "gets initial state on mount", %{session_id: session_id} do
      socket = %{assigns: %{}}

      {:ok, _socket, state} = SessionLV.mount_session(socket, session_id, @pubsub_name)

      assert state == %{user: "test", count: 0}
    end

    test "creates PubSub subscription", %{session_id: session_id} do
      socket = %{assigns: %{}}

      {:ok, _socket, _state} = SessionLV.mount_session(socket, session_id, @pubsub_name)

      # Verify we're subscribed by broadcasting a Redux message
      topic = "session:#{session_id}:redux"

      test_message = %{
        action: :test,
        state: %{test: "data"},
        timestamp: System.system_time(:millisecond)
      }

      Phoenix.PubSub.broadcast(@pubsub_name, topic, {:redux_state_change, test_message})

      # We should receive the broadcast
      assert_receive {:redux_state_change,
                      %{action: :test, state: %{test: "data"}, timestamp: _}},
                     100
    end

    test "sets socket assigns correctly", %{session_id: session_id} do
      socket = %{assigns: %{existing: "value"}}

      {:ok, updated_socket, _state} = SessionLV.mount_session(socket, session_id, @pubsub_name)

      # Check new assigns are added
      assert updated_socket.assigns.__session_id__ == session_id
      assert updated_socket.assigns.__session_pubsub__ == @pubsub_name
      # Check existing assigns are preserved
      assert updated_socket.assigns.existing == "value"
    end

    test "returns error when session doesn't exist" do
      socket = %{assigns: %{}}
      nonexistent_session = "nonexistent_session_id"

      result = SessionLV.mount_session(socket, nonexistent_session, @pubsub_name)

      assert {:error, {:session_not_found, ^nonexistent_session}} = result

      # Verify we're not subscribed to the topic
      topic = "session:#{nonexistent_session}:redux"

      test_message = %{
        action: :test,
        state: %{test: "data"},
        timestamp: System.system_time(:millisecond)
      }

      Phoenix.PubSub.broadcast(@pubsub_name, topic, {:redux_state_change, test_message})

      # We should NOT receive the broadcast
      refute_receive {:redux_state_change, _}, 100
    end
  end

  describe "mount_session/4 with custom state_key" do
    test "uses custom state_key parameter", %{session_id: session_id} do
      socket = %{assigns: %{}}

      # Call with custom state key
      result = SessionLV.mount_session(socket, session_id, @pubsub_name, :get_custom_state)

      assert {:ok, _socket, state} = result
      assert state == %{user: "test", count: 0}
    end

    test "returns error for unsupported state_key", %{session_id: session_id} do
      socket = %{assigns: %{}}

      # Call with an unsupported message - this will crash the session process
      # So we need to catch the exit
      Process.flag(:trap_exit, true)

      result =
        try do
          SessionLV.mount_session(socket, session_id, @pubsub_name, :invalid_message)
        catch
          :exit, _ -> {:error, :process_crashed}
        end

      # Should get an error (either from timeout or process crash)
      assert match?({:error, _}, result)

      Process.flag(:trap_exit, false)
    end
  end

  describe "unmount_session/1" do
    test "successfully unsubscribes from PubSub topic", %{session_id: session_id} do
      socket = %{assigns: %{}}

      # Mount first
      {:ok, socket, _state} = SessionLV.mount_session(socket, session_id, @pubsub_name)

      # Verify subscription works
      topic = "session:#{session_id}:redux"

      before_msg = %{
        action: :test,
        state: %{test: "before"},
        timestamp: System.system_time(:millisecond)
      }

      Phoenix.PubSub.broadcast(@pubsub_name, topic, {:redux_state_change, before_msg})
      assert_receive {:redux_state_change, %{state: %{test: "before"}}}, 100

      # Unmount
      assert :ok = SessionLV.unmount_session(socket)

      # Verify we're no longer subscribed
      after_msg = %{
        action: :test,
        state: %{test: "after"},
        timestamp: System.system_time(:millisecond)
      }

      Phoenix.PubSub.broadcast(@pubsub_name, topic, {:redux_state_change, after_msg})
      refute_receive {:redux_state_change, %{state: %{test: "after"}}}, 100
    end

    test "handles socket without session info gracefully" do
      socket = %{assigns: %{}}

      # Unmount without ever mounting
      assert :ok = SessionLV.unmount_session(socket)
    end

    test "handles socket with partial session info", %{session_id: session_id} do
      # Socket with only session_id, no pubsub
      socket = %{assigns: %{__session_id__: session_id}}

      assert :ok = SessionLV.unmount_session(socket)

      # Socket with only pubsub, no session_id
      socket = %{assigns: %{__session_pubsub__: @pubsub_name}}

      assert :ok = SessionLV.unmount_session(socket)
    end
  end

  describe "dispatch/2" do
    test "successfully calls session process", %{session_id: session_id} do
      result = SessionLV.dispatch(session_id, :get_state)

      assert result == {:ok, %{user: "test", count: 0}}
    end

    test "handles session not found errors" do
      result = SessionLV.dispatch("nonexistent_session", :get_state)

      assert {:error, {:session_not_found, "nonexistent_session"}} = result
    end

    test "passes parameters to session process", %{session_id: session_id} do
      # First dispatch a Redux action to change state
      SessionProcess.call(session_id, {:dispatch, {:put, :custom_key, "custom_value"}})

      # Then verify we can get the updated state
      {:ok, result} = SessionLV.dispatch(session_id, :get_state)

      assert result.custom_key == "custom_value"
    end
  end

  describe "dispatch_async/2" do
    test "successfully casts to session process", %{session_id: session_id} do
      result =
        SessionLV.dispatch_async(session_id, {:dispatch_async, {:put, :async_key, "async_value"}})

      assert result == :ok

      # Verify the cast was processed
      Process.sleep(10)
      {:ok, state} = SessionProcess.call(session_id, :get_state)
      assert state.async_key == "async_value"
    end

    test "handles session not found errors" do
      result = SessionLV.dispatch_async("nonexistent_session", {:some, :message})

      assert {:error, {:session_not_found, "nonexistent_session"}} = result
    end
  end

  describe "session_topic/1" do
    test "returns correct topic format", %{session_id: session_id} do
      topic = SessionLV.session_topic(session_id)

      assert topic == "session:#{session_id}:redux"
    end

    test "generates unique topics for different sessions" do
      session_id1 = "session_1"
      session_id2 = "session_2"

      topic1 = SessionLV.session_topic(session_id1)
      topic2 = SessionLV.session_topic(session_id2)

      assert topic1 == "session:session_1:redux"
      assert topic2 == "session:session_2:redux"
      assert topic1 != topic2
    end
  end

  describe "subscribe/2" do
    test "successfully subscribes to session topic", %{session_id: session_id} do
      result = SessionLV.subscribe(session_id, @pubsub_name)

      assert result == :ok

      # Verify subscription by broadcasting
      topic = SessionLV.session_topic(session_id)
      Phoenix.PubSub.broadcast(@pubsub_name, topic, {:test_message, "hello"})

      assert_receive {:test_message, "hello"}, 100
    end

    test "allows multiple subscribers to same session", %{session_id: session_id} do
      # Subscribe from current process
      SessionLV.subscribe(session_id, @pubsub_name)

      # Subscribe from another process
      parent = self()

      spawn(fn ->
        SessionLV.subscribe(session_id, @pubsub_name)
        send(parent, :subscribed)

        receive do
          {:test_broadcast, data} -> send(parent, {:received, data})
        end
      end)

      assert_receive :subscribed, 100

      # Broadcast to the topic
      topic = SessionLV.session_topic(session_id)
      Phoenix.PubSub.broadcast(@pubsub_name, topic, {:test_broadcast, "data"})

      # Both should receive
      assert_receive {:test_broadcast, "data"}, 100
      assert_receive {:received, "data"}, 100
    end
  end

  describe "unsubscribe/2" do
    test "successfully unsubscribes from session topic", %{session_id: session_id} do
      # Subscribe first
      SessionLV.subscribe(session_id, @pubsub_name)

      # Verify subscription
      topic = SessionLV.session_topic(session_id)
      Phoenix.PubSub.broadcast(@pubsub_name, topic, {:before_unsub, "data"})
      assert_receive {:before_unsub, "data"}, 100

      # Unsubscribe
      result = SessionLV.unsubscribe(session_id, @pubsub_name)
      assert result == :ok

      # Verify unsubscription
      Phoenix.PubSub.broadcast(@pubsub_name, topic, {:after_unsub, "data"})
      refute_receive {:after_unsub, "data"}, 100
    end

    test "can unsubscribe without being subscribed", %{session_id: session_id} do
      # This should not raise an error
      result = SessionLV.unsubscribe(session_id, @pubsub_name)

      assert result == :ok
    end
  end
end
