defmodule Phoenix.SessionProcess.DispatchTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess

  defmodule TestSessionProcess do
    use Phoenix.SessionProcess, :process

    def user_init(_arg) do
      %{count: 0, user: nil}
    end
  end

  setup do
    session_id = "test_session_#{:rand.uniform(1_000_000)}"
    {:ok, _pid} = SessionProcess.start(session_id, TestSessionProcess)

    # Register a simple reducer
    reducer = fn action, state ->
      case action do
        :increment -> %{state | count: state.count + 1}
        {:set_count, value} -> %{state | count: value}
        {:set_user, user} -> %{state | user: user}
        _ -> state
      end
    end

    :ok = SessionProcess.register_reducer(session_id, :test_reducer, reducer)

    on_exit(fn ->
      if SessionProcess.started?(session_id) do
        SessionProcess.terminate(session_id)
      end
    end)

    %{session_id: session_id}
  end

  describe "dispatch/3" do
    test "synchronous dispatch returns new state", %{session_id: session_id} do
      {:ok, new_state} = SessionProcess.dispatch(session_id, :increment)

      assert new_state.count == 1
      assert new_state.user == nil
    end

    test "multiple dispatches accumulate state changes", %{session_id: session_id} do
      {:ok, _} = SessionProcess.dispatch(session_id, :increment)
      {:ok, _} = SessionProcess.dispatch(session_id, :increment)
      {:ok, state} = SessionProcess.dispatch(session_id, :increment)

      assert state.count == 3
    end

    test "dispatch with different actions", %{session_id: session_id} do
      {:ok, state1} = SessionProcess.dispatch(session_id, {:set_count, 10})
      assert state1.count == 10

      {:ok, state2} = SessionProcess.dispatch(session_id, {:set_user, "alice"})
      assert state2.user == "alice"
      assert state2.count == 10
    end

    test "asynchronous dispatch returns :ok", %{session_id: session_id} do
      result = SessionProcess.dispatch(session_id, :increment, async: true)
      assert result == :ok

      # Wait a bit for async processing
      Process.sleep(10)

      # Verify state changed
      state = SessionProcess.get_state(session_id)
      assert state.count == 1
    end

    test "dispatch with custom timeout", %{session_id: session_id} do
      {:ok, state} = SessionProcess.dispatch(session_id, :increment, timeout: 10_000)
      assert state.count == 1
    end

    test "dispatch to non-existent session returns error", %{} do
      result = SessionProcess.dispatch("nonexistent_session", :increment)
      assert {:error, {:session_not_found, "nonexistent_session"}} == result
    end

    test "async dispatch to non-existent session returns error", %{} do
      result = SessionProcess.dispatch("nonexistent_session", :increment, async: true)
      assert {:error, {:session_not_found, "nonexistent_session"}} == result
    end
  end

  describe "get_state/2" do
    test "gets full state without selector", %{session_id: session_id} do
      {:ok, _} = SessionProcess.dispatch(session_id, :increment)

      state = SessionProcess.get_state(session_id)
      assert state.count == 1
      assert state.user == nil
    end

    test "gets state with inline selector function", %{session_id: session_id} do
      {:ok, _} = SessionProcess.dispatch(session_id, {:set_count, 42})

      count = SessionProcess.get_state(session_id, fn s -> s.count end)
      assert count == 42
    end

    test "gets state with registered selector", %{session_id: session_id} do
      # Register a named selector
      :ok = SessionProcess.register_selector(session_id, :count, fn s -> s.count end)

      {:ok, _} = SessionProcess.dispatch(session_id, {:set_count, 99})

      count = SessionProcess.get_state(session_id, :count)
      assert count == 99
    end
  end

  describe "subscribe/4 and unsubscribe/2" do
    test "subscribes to state changes and receives notifications", %{session_id: session_id} do
      # Subscribe to count changes
      {:ok, sub_id} =
        SessionProcess.subscribe(session_id, fn s -> s.count end, :count_changed)

      # Receive initial value
      assert_receive {:count_changed, 0}, 1000

      # Dispatch action
      {:ok, _} = SessionProcess.dispatch(session_id, :increment)

      # Receive update
      assert_receive {:count_changed, 1}, 1000

      # Cleanup
      :ok = SessionProcess.unsubscribe(session_id, sub_id)
    end

    test "only notifies when selected value changes", %{session_id: session_id} do
      # Subscribe to count
      {:ok, sub_id} =
        SessionProcess.subscribe(session_id, fn s -> s.count end, :count_changed)

      # Clear initial message
      assert_receive {:count_changed, 0}, 1000

      # Change user (not count)
      {:ok, _} = SessionProcess.dispatch(session_id, {:set_user, "bob"})

      # Should NOT receive notification
      refute_receive {:count_changed, _}, 100

      # Now change count
      {:ok, _} = SessionProcess.dispatch(session_id, :increment)

      # Should receive notification
      assert_receive {:count_changed, 1}, 1000

      :ok = SessionProcess.unsubscribe(session_id, sub_id)
    end

    test "multiple subscribers receive notifications", %{session_id: session_id} do
      # Two subscribers to count
      {:ok, sub_id1} =
        SessionProcess.subscribe(session_id, fn s -> s.count end, :count_changed_1)

      {:ok, sub_id2} =
        SessionProcess.subscribe(session_id, fn s -> s.count end, :count_changed_2)

      # Clear initial messages
      assert_receive {:count_changed_1, 0}, 1000
      assert_receive {:count_changed_2, 0}, 1000

      # Dispatch
      {:ok, _} = SessionProcess.dispatch(session_id, :increment)

      # Both should receive
      assert_receive {:count_changed_1, 1}, 1000
      assert_receive {:count_changed_2, 1}, 1000

      :ok = SessionProcess.unsubscribe(session_id, sub_id1)
      :ok = SessionProcess.unsubscribe(session_id, sub_id2)
    end

    test "unsubscribe stops notifications", %{session_id: session_id} do
      {:ok, sub_id} =
        SessionProcess.subscribe(session_id, fn s -> s.count end, :count_changed)

      assert_receive {:count_changed, 0}, 1000

      # Unsubscribe
      :ok = SessionProcess.unsubscribe(session_id, sub_id)

      # Dispatch
      {:ok, _} = SessionProcess.dispatch(session_id, :increment)

      # Should NOT receive
      refute_receive {:count_changed, _}, 100
    end

    test "subscription cleans up when subscriber process dies", %{session_id: session_id} do
      # Spawn subscriber process
      parent = self()

      subscriber =
        spawn(fn ->
          {:ok, sub_id} =
            SessionProcess.subscribe(session_id, fn s -> s.count end, :count_changed)

          send(parent, {:subscribed, sub_id})

          # Wait for termination signal
          receive do
            :exit -> :ok
          end
        end)

      # Wait for subscription
      assert_receive {:subscribed, _sub_id}, 1000

      # Kill subscriber
      Process.exit(subscriber, :kill)
      Process.sleep(50)

      # Dispatch should not crash
      {:ok, _} = SessionProcess.dispatch(session_id, :increment)
    end
  end

  describe "register_selector/3 and select/2" do
    test "registers and uses named selector", %{session_id: session_id} do
      # Register selector
      :ok = SessionProcess.register_selector(session_id, :count, fn s -> s.count end)

      {:ok, _} = SessionProcess.dispatch(session_id, {:set_count, 123})

      # Use select function
      count = SessionProcess.select(session_id, :count)
      assert count == 123
    end

    test "registers complex selector", %{session_id: session_id} do
      # Register a computed selector
      :ok =
        SessionProcess.register_selector(session_id, :doubled_count, fn s -> s.count * 2 end)

      {:ok, _} = SessionProcess.dispatch(session_id, {:set_count, 5})

      doubled = SessionProcess.select(session_id, :doubled_count)
      assert doubled == 10
    end

    test "select returns error for non-existent selector", %{session_id: session_id} do
      result = SessionProcess.select(session_id, :nonexistent)
      assert {:error, {:selector_not_found, :nonexistent}} == result
    end
  end

  describe "register_reducer/3" do
    test "can register multiple reducers", %{session_id: session_id} do
      # Add another reducer
      multiplier_reducer = fn action, state ->
        case action do
          {:multiply_count, factor} -> %{state | count: state.count * factor}
          _ -> state
        end
      end

      :ok = SessionProcess.register_reducer(session_id, :multiplier, multiplier_reducer)

      # First reducer increments
      {:ok, state1} = SessionProcess.dispatch(session_id, :increment)
      assert state1.count == 1

      # Second reducer multiplies
      {:ok, state2} = SessionProcess.dispatch(session_id, {:multiply_count, 5})
      assert state2.count == 5
    end

    test "reducers are applied in order", %{session_id: session_id} do
      # Add reducer that doubles
      doubler = fn action, state ->
        case action do
          :double -> %{state | count: state.count * 2}
          _ -> state
        end
      end

      :ok = SessionProcess.register_reducer(session_id, :doubler, doubler)

      {:ok, _} = SessionProcess.dispatch(session_id, {:set_count, 5})
      {:ok, state} = SessionProcess.dispatch(session_id, :double)

      assert state.count == 10
    end
  end
end
