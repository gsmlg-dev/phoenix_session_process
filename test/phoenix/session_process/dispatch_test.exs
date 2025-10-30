defmodule Phoenix.SessionProcess.DispatchTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess

  defmodule TestReducer do
    use Phoenix.SessionProcess, :reducer

    @name :test_reducer

    def init_state do
      %{count: 0, user: nil}
    end

    def handle_action(action, state) do
      alias Phoenix.SessionProcess.Action

      case action do
        %Action{type: "increment"} ->
          %{state | count: state.count + 1}

        %Action{type: "set_count", payload: value} ->
          %{state | count: value}

        %Action{type: "set_user", payload: user} ->
          %{state | user: user}

        %Action{type: "multiply_count", payload: factor} ->
          %{state | count: state.count * factor}

        %Action{type: "double"} ->
          %{state | count: state.count * 2}

        _ ->
          state
      end
    end
  end

  defmodule TestSessionProcess do
    use Phoenix.SessionProcess, :process

    def init_state(_arg) do
      %{}
    end

    def combined_reducers do
      [TestReducer]
    end
  end

  setup do
    session_id = "test_session_#{:rand.uniform(1_000_000)}"
    {:ok, _pid} = SessionProcess.start(session_id, TestSessionProcess)

    on_exit(fn ->
      if SessionProcess.started?(session_id) do
        SessionProcess.terminate(session_id)
      end
    end)

    %{session_id: session_id}
  end

  describe "dispatch/4" do
    test "dispatch returns :ok", %{session_id: session_id} do
      result = SessionProcess.dispatch(session_id, "increment")
      assert result == :ok

      # Verify state changed
      state = SessionProcess.get_state(session_id)
      assert state.test_reducer.count == 1
      assert state.test_reducer.user == nil
    end

    test "multiple dispatches accumulate state changes", %{session_id: session_id} do
      :ok = SessionProcess.dispatch(session_id, "increment")
      :ok = SessionProcess.dispatch(session_id, "increment")
      :ok = SessionProcess.dispatch(session_id, "increment")

      # Wait a bit for async processing
      Process.sleep(10)

      state = SessionProcess.get_state(session_id)
      assert state.test_reducer.count == 3
    end

    test "dispatch with different actions", %{session_id: session_id} do
      :ok = SessionProcess.dispatch(session_id, "set_count", 10)
      Process.sleep(10)

      state1 = SessionProcess.get_state(session_id)
      assert state1.test_reducer.count == 10

      :ok = SessionProcess.dispatch(session_id, "set_user", "alice")
      Process.sleep(10)

      state2 = SessionProcess.get_state(session_id)
      assert state2.test_reducer.user == "alice"
      assert state2.test_reducer.count == 10
    end

    test "dispatch_async returns {:ok, cancel_fn}", %{session_id: session_id} do
      result = SessionProcess.dispatch_async(session_id, "increment")
      assert {:ok, cancel_fn} = result
      assert is_function(cancel_fn, 0)

      # Wait a bit for async processing
      Process.sleep(10)

      # Verify state changed
      state = SessionProcess.get_state(session_id)
      assert state.test_reducer.count == 1
    end

    test "dispatch_async returns cancellation function", %{session_id: session_id} do
      # Dispatch async action
      {:ok, cancel_fn} = SessionProcess.dispatch_async(session_id, "increment")

      # Cancellation function can be called (best-effort cancellation)
      assert :ok = cancel_fn.()

      # Note: Due to race conditions, we can't reliably test that the action
      # was actually cancelled. The cancel is best-effort - if the action
      # has already been processed before the cancel message arrives, it won't be cancelled.
      # This test just verifies that the cancel function works without errors.
    end

    test "dispatch to non-existent session returns error", %{} do
      result = SessionProcess.dispatch("nonexistent_session", "increment")
      assert {:error, {:session_not_found, "nonexistent_session"}} == result
    end

    test "dispatch_async to non-existent session returns error", %{} do
      result = SessionProcess.dispatch_async("nonexistent_session", "increment")
      assert {:error, {:session_not_found, "nonexistent_session"}} == result
    end

    test "dispatch validates action type is binary" do
      session_id = "validate_session_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start(session_id, TestSessionProcess)

      assert_raise ArgumentError, ~r/Action type must be a binary string/, fn ->
        SessionProcess.dispatch(session_id, :atom_type)
      end

      SessionProcess.terminate(session_id)
    end

    test "dispatch validates meta is a keyword list" do
      session_id = "validate_meta_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start(session_id, TestSessionProcess)

      assert_raise ArgumentError, ~r/Action meta must be a keyword list/, fn ->
        SessionProcess.dispatch(session_id, "test", nil, %{async: true})
      end

      SessionProcess.terminate(session_id)
    end
  end

  describe "get_state/2" do
    test "gets full state without selector", %{session_id: session_id} do
      :ok = SessionProcess.dispatch(session_id, "increment")
      Process.sleep(10)

      state = SessionProcess.get_state(session_id)
      assert state.test_reducer.count == 1
      assert state.test_reducer.user == nil
    end

    test "gets state with inline selector function", %{session_id: session_id} do
      :ok = SessionProcess.dispatch(session_id, "set_count", 42)
      Process.sleep(10)

      count = SessionProcess.get_state(session_id, fn s -> s.test_reducer.count end)
      assert count == 42
    end
  end

  describe "select_state/2" do
    test "selects state on server side", %{session_id: session_id} do
      :ok = SessionProcess.dispatch(session_id, "set_count", 42)
      Process.sleep(10)

      count = SessionProcess.select_state(session_id, fn s -> s.test_reducer.count end)
      assert count == 42
    end

    test "selects nested data", %{session_id: session_id} do
      :ok = SessionProcess.dispatch(session_id, "set_user", "alice")
      Process.sleep(10)

      user = SessionProcess.select_state(session_id, fn s -> s.test_reducer.user end)
      assert user == "alice"
    end

    test "selects computed value", %{session_id: session_id} do
      :ok = SessionProcess.dispatch(session_id, "set_count", 10)
      Process.sleep(10)

      doubled = SessionProcess.select_state(session_id, fn s -> s.test_reducer.count * 2 end)
      assert doubled == 20
    end

    test "returns error for non-existent session" do
      result = SessionProcess.select_state("nonexistent_session", fn s -> s end)
      assert {:error, {:session_not_found, "nonexistent_session"}} == result
    end
  end

  describe "subscribe/4 and unsubscribe/2" do
    test "subscribes to state changes and receives notifications", %{session_id: session_id} do
      # Subscribe to count changes
      {:ok, sub_id} =
        SessionProcess.subscribe(session_id, fn s -> s.test_reducer.count end, :count_changed)

      # Receive initial value
      assert_receive {:count_changed, 0}, 1000

      # Dispatch action
      :ok = SessionProcess.dispatch(session_id, "increment")

      # Receive update
      assert_receive {:count_changed, 1}, 1000

      # Cleanup
      :ok = SessionProcess.unsubscribe(session_id, sub_id)
    end

    test "only notifies when selected value changes", %{session_id: session_id} do
      # Subscribe to count
      {:ok, sub_id} =
        SessionProcess.subscribe(session_id, fn s -> s.test_reducer.count end, :count_changed)

      # Clear initial message
      assert_receive {:count_changed, 0}, 1000

      # Change user (not count)
      :ok = SessionProcess.dispatch(session_id, "set_user", "bob")

      # Should NOT receive notification
      refute_receive {:count_changed, _}, 100

      # Now change count
      :ok = SessionProcess.dispatch(session_id, "increment")

      # Should receive notification
      assert_receive {:count_changed, 1}, 1000

      :ok = SessionProcess.unsubscribe(session_id, sub_id)
    end

    test "multiple subscribers receive notifications", %{session_id: session_id} do
      # Two subscribers to count
      {:ok, sub_id1} =
        SessionProcess.subscribe(session_id, fn s -> s.test_reducer.count end, :count_changed_1)

      {:ok, sub_id2} =
        SessionProcess.subscribe(session_id, fn s -> s.test_reducer.count end, :count_changed_2)

      # Clear initial messages
      assert_receive {:count_changed_1, 0}, 1000
      assert_receive {:count_changed_2, 0}, 1000

      # Dispatch
      :ok = SessionProcess.dispatch(session_id, "increment")

      # Both should receive
      assert_receive {:count_changed_1, 1}, 1000
      assert_receive {:count_changed_2, 1}, 1000

      :ok = SessionProcess.unsubscribe(session_id, sub_id1)
      :ok = SessionProcess.unsubscribe(session_id, sub_id2)
    end

    test "unsubscribe stops notifications", %{session_id: session_id} do
      {:ok, sub_id} =
        SessionProcess.subscribe(session_id, fn s -> s.test_reducer.count end, :count_changed)

      assert_receive {:count_changed, 0}, 1000

      # Unsubscribe
      :ok = SessionProcess.unsubscribe(session_id, sub_id)

      # Dispatch
      :ok = SessionProcess.dispatch(session_id, "increment")

      # Should NOT receive
      refute_receive {:count_changed, _}, 100
    end

    test "subscription cleans up when subscriber process dies", %{session_id: session_id} do
      # Spawn subscriber process
      parent = self()

      subscriber =
        spawn(fn ->
          {:ok, sub_id} =
            SessionProcess.subscribe(
              session_id,
              fn s -> s.test_reducer.count end,
              :count_changed
            )

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
      :ok = SessionProcess.dispatch(session_id, "increment")
    end
  end

  describe "combined_reducers with multiple reducers" do
    test "multiple reducer instances with different actions", %{session_id: session_id} do
      # Test that actions trigger reducers correctly
      :ok = SessionProcess.dispatch(session_id, "increment")
      Process.sleep(10)
      state1 = SessionProcess.get_state(session_id)
      assert state1.test_reducer.count == 1

      # Test multiply
      :ok = SessionProcess.dispatch(session_id, "multiply_count", 5)
      Process.sleep(10)
      state2 = SessionProcess.get_state(session_id)
      assert state2.test_reducer.count == 5
    end

    test "reducers are applied in order", %{session_id: session_id} do
      :ok = SessionProcess.dispatch(session_id, "set_count", 5)
      :ok = SessionProcess.dispatch(session_id, "double")
      Process.sleep(10)

      state = SessionProcess.get_state(session_id)
      assert state.test_reducer.count == 10
    end
  end
end
