defmodule Phoenix.SessionProcess.ReducerIntegrationTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess

  # Test reducer module with throttle and debounce
  defmodule UserReducer do
    use Phoenix.SessionProcess, :reducer

    def init_state do
      %{users: [], fetch_count: 0, search_query: nil}
    end

    @throttle {"fetch-users", "100ms"}
    def handle_action(%{type: "fetch-users"}, state) do
      Map.update(state, :fetch_count, 1, &(&1 + 1))
    end

    @debounce {"search-users", "50ms"}
    def handle_action(%{type: "search-users", payload: query}, state) do
      Map.put(state, :search_query, query)
    end

    def handle_action(%{type: "add-user", payload: user}, state) do
      Map.update(state, :users, [user], &[user | &1])
    end

    def handle_action(_action, state), do: state
  end

  # Another reducer for testing multiple reducers
  defmodule CartReducer do
    use Phoenix.SessionProcess, :reducer

    def init_state do
      %{items: []}
    end

    def handle_action(%{type: "add-item", payload: item}, state) do
      Map.update(state, :items, [item], &[item | &1])
    end

    def handle_action(%{type: "clear-cart"}, state) do
      Map.put(state, :items, [])
    end

    def handle_action(_action, state), do: state
  end

  # Test session process with combined reducers
  defmodule TestSessionProcess do
    use Phoenix.SessionProcess, :process

    def init_state(_arg) do
      # Only define state not managed by reducers
      %{global_count: 0}
    end

    def combined_reducers do
      %{
        users: UserReducer,
        cart: CartReducer
      }
    end
  end

  setup do
    session_id = "test_session_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = SessionProcess.start(session_id, TestSessionProcess)

    on_exit(fn ->
      if Process.alive?(pid) do
        SessionProcess.terminate(session_id)
      end
    end)

    %{session_id: session_id, pid: pid}
  end

  describe "reducer modules" do
    test "verifies reducer init_state is called for each slice", %{session_id: session_id} do
      state = SessionProcess.get_state(session_id)

      # Verify users slice was initialized from UserReducer.init_state/0
      assert state.users == %{users: [], fetch_count: 0, search_query: nil}

      # Verify cart slice was initialized from CartReducer.init_state/0
      assert state.cart == %{items: []}

      # Verify global state from SessionProcess init_state/1
      assert state.global_count == 0
    end

    test "verifies reducer module metadata functions exist", %{session_id: _session_id} do
      # Check throttle metadata
      assert [{_, "100ms"}] = UserReducer.__reducer_throttles__()
      assert UserReducer.__reducer_module__() == true

      # Check debounce metadata
      assert [{_, "50ms"}] = UserReducer.__reducer_debounces__()

      # CartReducer should have no throttles/debounces
      assert CartReducer.__reducer_throttles__() == []
      assert CartReducer.__reducer_debounces__() == []
      assert CartReducer.__reducer_module__() == true
    end

    test "verifies init_state delegates to user_init for backward compatibility" do
      defmodule LegacySessionProcess do
        use Phoenix.SessionProcess, :process

        def user_init(_arg) do
          %{legacy: true, count: 100}
        end
      end

      session_id = "legacy_session_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start(session_id, LegacySessionProcess)

      state = SessionProcess.get_state(session_id)
      assert state.legacy == true
      assert state.count == 100

      SessionProcess.terminate(session_id)
    end
  end

  describe "combined reducers" do
    test "routes actions to the correct reducer slice", %{session_id: session_id} do
      # Dispatch to UserReducer
      SessionProcess.dispatch(session_id, %{type: "add-user", payload: "Alice"})

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]
      assert state.cart.items == []

      # Dispatch to CartReducer
      SessionProcess.dispatch(session_id, %{type: "add-item", payload: "Book"})

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]
      assert state.cart.items == ["Book"]
    end

    test "multiple actions to different reducers", %{session_id: session_id} do
      SessionProcess.dispatch(session_id, %{type: "add-user", payload: "Alice"})
      SessionProcess.dispatch(session_id, %{type: "add-user", payload: "Bob"})
      SessionProcess.dispatch(session_id, %{type: "add-item", payload: "Book"})
      SessionProcess.dispatch(session_id, %{type: "add-item", payload: "Pen"})

      state = SessionProcess.get_state(session_id)
      assert length(state.users.users) == 2
      assert length(state.cart.items) == 2
    end

    test "clearing one slice doesn't affect others", %{session_id: session_id} do
      SessionProcess.dispatch(session_id, %{type: "add-user", payload: "Alice"})
      SessionProcess.dispatch(session_id, %{type: "add-item", payload: "Book"})

      # Clear cart
      SessionProcess.dispatch(session_id, %{type: "clear-cart"})

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]
      assert state.cart.items == []
    end
  end

  describe "throttle functionality" do
    test "throttles rapid action dispatches", %{session_id: session_id} do
      # First call should execute
      SessionProcess.dispatch(session_id, %{type: "fetch-users"})

      state1 = SessionProcess.get_state(session_id)
      assert state1.users.fetch_count == 1

      # Rapid calls within throttle window (100ms) should be blocked
      SessionProcess.dispatch(session_id, %{type: "fetch-users"})
      SessionProcess.dispatch(session_id, %{type: "fetch-users"})

      state2 = SessionProcess.get_state(session_id)
      # Count should still be 1 (throttled)
      assert state2.users.fetch_count == 1

      # Wait for throttle window to pass
      Process.sleep(150)

      # Now it should execute again
      SessionProcess.dispatch(session_id, %{type: "fetch-users"})

      state3 = SessionProcess.get_state(session_id)
      assert state3.users.fetch_count == 2
    end
  end

  describe "debounce functionality" do
    test "debounces rapid action dispatches", %{session_id: session_id} do
      # Rapid dispatches - only last one should execute after delay
      SessionProcess.dispatch(session_id, %{type: "search-users", payload: "a"})
      Process.sleep(10)
      SessionProcess.dispatch(session_id, %{type: "search-users", payload: "ab"})
      Process.sleep(10)
      SessionProcess.dispatch(session_id, %{type: "search-users", payload: "abc"})

      # Immediately after, state should not be updated yet
      state1 = SessionProcess.get_state(session_id)
      assert state1.users.search_query == nil

      # Wait for debounce delay (50ms + buffer)
      Process.sleep(100)

      # Now the last value should be set
      state2 = SessionProcess.get_state(session_id)
      assert state2.users.search_query == "abc"
    end
  end

  describe "subscriptions with combined reducers" do
    test "subscribes to state changes in a specific slice", %{session_id: session_id} do
      # Subscribe to user slice
      {:ok, _sub_id} =
        SessionProcess.subscribe(
          session_id,
          fn state -> length(state.users.users) end,
          :user_count_changed,
          self()
        )

      # Initial notification
      assert_receive {:user_count_changed, 0}

      # Add user - should trigger notification
      SessionProcess.dispatch(session_id, %{type: "add-user", payload: "Alice"})
      assert_receive {:user_count_changed, 1}

      # Add cart item - should NOT trigger notification (different slice)
      SessionProcess.dispatch(session_id, %{type: "add-item", payload: "Book"})
      refute_receive {:user_count_changed, _}, 100
    end

    test "multiple subscriptions to different slices", %{session_id: session_id} do
      {:ok, _} =
        SessionProcess.subscribe(
          session_id,
          fn state -> length(state.users.users) end,
          :user_count,
          self()
        )

      {:ok, _} =
        SessionProcess.subscribe(
          session_id,
          fn state -> length(state.cart.items) end,
          :cart_count,
          self()
        )

      # Clear initial notifications
      assert_receive {:user_count, 0}
      assert_receive {:cart_count, 0}

      # Dispatch to both slices
      SessionProcess.dispatch(session_id, %{type: "add-user", payload: "Alice"})
      SessionProcess.dispatch(session_id, %{type: "add-item", payload: "Book"})

      assert_receive {:user_count, 1}
      assert_receive {:cart_count, 1}
    end
  end

  describe "manually registered reducers alongside combined reducers" do
    test "manually registered reducers can access full state" do
      session_id = "manual_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start(session_id, TestSessionProcess)

      # Register a manual reducer that works on global state
      manual_reducer = fn action, state ->
        case action do
          :increment_global ->
            Map.update(state, :global_count, 1, &(&1 + 1))

          _ ->
            state
        end
      end

      :ok = SessionProcess.register_reducer(session_id, :global_reducer, manual_reducer)

      # Dispatch action to manual reducer
      SessionProcess.dispatch(session_id, :increment_global)

      state = SessionProcess.get_state(session_id)
      assert state.global_count == 1

      # Verify combined reducers still work
      SessionProcess.dispatch(session_id, %{type: "add-user", payload: "Alice"})
      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]
      assert state.global_count == 1

      SessionProcess.terminate(session_id)
    end
  end

  describe "error handling" do
    test "unknown actions don't break reducer", %{session_id: session_id} do
      # Dispatch unknown action
      SessionProcess.dispatch(session_id, %{type: "unknown-action"})

      # State should be unchanged
      state = SessionProcess.get_state(session_id)
      assert state.users.users == []
      assert state.cart.items == []
    end

    test "action without matching slice continues", %{session_id: session_id} do
      # Dispatch action that doesn't match any slice's handlers
      SessionProcess.dispatch(session_id, %{type: "random-action"})

      state = SessionProcess.get_state(session_id)
      assert state.users.users == []
      assert state.cart.items == []
    end
  end
end
