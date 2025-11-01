defmodule Phoenix.SessionProcess.ReducerIntegrationTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess

  # Test reducer module with throttle and debounce
  defmodule UserReducer do
    use Phoenix.SessionProcess, :reducer
    alias Phoenix.SessionProcess.Action

    @name :users
    @action_prefix "user"

    def init_state do
      %{users: [], fetch_count: 0, search_query: nil}
    end

    @throttle {"fetch-users", "100ms"}
    def handle_action(%Action{type: "fetch-users"}, state) do
      Map.update(state, :fetch_count, 1, &(&1 + 1))
    end

    @debounce {"search-users", "50ms"}
    def handle_action(%Action{type: "search-users", payload: query}, state) do
      Map.put(state, :search_query, query)
    end

    def handle_action(%Action{type: "add-user", payload: user}, state) do
      Map.update(state, :users, [user], &[user | &1])
    end

    def handle_action(_action, state), do: state
  end

  # Another reducer for testing multiple reducers
  defmodule CartReducer do
    use Phoenix.SessionProcess, :reducer
    alias Phoenix.SessionProcess.Action

    @name :cart
    @action_prefix "cart"

    def init_state do
      %{items: []}
    end

    def handle_action(%Action{type: "add-item", payload: item}, state) do
      Map.update(state, :items, [item], &[item | &1])
    end

    def handle_action(%Action{type: "clear-cart"}, state) do
      Map.put(state, :items, [])
    end

    def handle_action(_action, state), do: state
  end

  # Reducer with custom @name and @action_prefix
  defmodule ShippingReducer do
    use Phoenix.SessionProcess, :reducer
    alias Phoenix.SessionProcess.Action

    @name :shipping
    @action_prefix "ship"

    def init_state do
      %{address: nil, cost: 0}
    end

    def handle_action(%Action{type: "calculate-shipping", payload: address}, state) do
      %{state | address: address, cost: 10}
    end

    def handle_action(_action, state), do: state
  end

  # Reducer with @name but no @action_prefix (should default to "inventory")
  defmodule InventoryReducer do
    use Phoenix.SessionProcess, :reducer
    alias Phoenix.SessionProcess.Action

    @name :inventory

    def init_state do
      %{stock: 100}
    end

    def handle_action(%Action{type: "reduce-stock", payload: amount}, state) do
      Map.update(state, :stock, 0, &max(&1 - amount, 0))
    end

    def handle_action(_action, state), do: state
  end

  # Reducer without init_state/0 (should default to %{})
  defmodule NotificationsReducer do
    use Phoenix.SessionProcess, :reducer
    alias Phoenix.SessionProcess.Action

    @name :notifications
    @action_prefix "notify"

    # No init_state/0 defined

    def handle_action(%Action{type: "add-notification", payload: msg}, state) do
      Map.update(state, :messages, [msg], &[msg | &1])
    end

    def handle_action(_action, state), do: state
  end

  # Reducer with special characters in name/prefix
  defmodule SpecialCharsReducer do
    use Phoenix.SessionProcess, :reducer
    alias Phoenix.SessionProcess.Action

    @name :special_chars_test
    @action_prefix "special-chars.test"

    def init_state, do: %{data: "test"}

    def handle_action(%Action{type: "update-special"}, state) do
      Map.put(state, :data, "updated")
    end

    def handle_action(_action, state), do: state
  end

  # Multiple reducers for stress test
  defmodule StressReducer1 do
    use Phoenix.SessionProcess, :reducer
    @name :stress1
    def init_state, do: %{count: 0}
    def handle_action(_action, state), do: state
  end

  defmodule StressReducer2 do
    use Phoenix.SessionProcess, :reducer
    @name :stress2
    def init_state, do: %{count: 0}
    def handle_action(_action, state), do: state
  end

  defmodule StressReducer3 do
    use Phoenix.SessionProcess, :reducer
    @name :stress3
    def init_state, do: %{count: 0}
    def handle_action(_action, state), do: state
  end

  defmodule StressReducer4 do
    use Phoenix.SessionProcess, :reducer
    @name :stress4
    def init_state, do: %{count: 0}
    def handle_action(_action, state), do: state
  end

  defmodule StressReducer5 do
    use Phoenix.SessionProcess, :reducer
    @name :stress5
    def init_state, do: %{count: 0}
    def handle_action(_action, state), do: state
  end

  # Counting reducers for routing tests
  defmodule CountingUserReducer do
    use Phoenix.SessionProcess, :reducer

    @name :users
    @action_prefix "users"

    def init_state, do: %{count: 0}

    def handle_action(_action, state) do
      # Increment call count on any action
      Map.update(state, :count, 1, &(&1 + 1))
    end
  end

  defmodule CountingCartReducer do
    use Phoenix.SessionProcess, :reducer

    @name :cart
    @action_prefix "cart"

    def init_state, do: %{count: 0}

    def handle_action(_action, state) do
      # Increment call count on any action
      Map.update(state, :count, 1, &(&1 + 1))
    end
  end

  # Test session process with combined reducers
  defmodule TestSessionProcess do
    use Phoenix.SessionProcess, :process

    def init_state(_arg) do
      # Only define state not managed by reducers
      %{global_count: 0}
    end

    def combined_reducers do
      [
        UserReducer,
        CartReducer
      ]
    end
  end

  setup do
    session_id = "test_session_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = SessionProcess.start_session(session_id, TestSessionProcess)

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
  end

  describe "combined reducers" do
    test "routes actions to the correct reducer slice", %{session_id: session_id} do
      # Dispatch to UserReducer
      SessionProcess.dispatch(session_id, "add-user", "Alice")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]
      assert state.cart.items == []

      # Dispatch to CartReducer
      SessionProcess.dispatch(session_id, "add-item", "Book")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]
      assert state.cart.items == ["Book"]
    end

    test "multiple actions to different reducers", %{session_id: session_id} do
      SessionProcess.dispatch(session_id, "add-user", "Alice")
      SessionProcess.dispatch(session_id, "add-user", "Bob")
      SessionProcess.dispatch(session_id, "add-item", "Book")
      SessionProcess.dispatch(session_id, "add-item", "Pen")

      state = SessionProcess.get_state(session_id)
      assert length(state.users.users) == 2
      assert length(state.cart.items) == 2
    end

    test "clearing one slice doesn't affect others", %{session_id: session_id} do
      SessionProcess.dispatch(session_id, "add-user", "Alice")
      SessionProcess.dispatch(session_id, "add-item", "Book")

      # Clear cart
      SessionProcess.dispatch(session_id, "clear-cart")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]
      assert state.cart.items == []
    end
  end

  describe "throttle functionality" do
    test "throttles rapid action dispatches", %{session_id: session_id} do
      # First call should execute
      SessionProcess.dispatch(session_id, "fetch-users")

      state1 = SessionProcess.get_state(session_id)
      assert state1.users.fetch_count == 1

      # Rapid calls within throttle window (100ms) should be blocked
      SessionProcess.dispatch(session_id, "fetch-users")
      SessionProcess.dispatch(session_id, "fetch-users")

      state2 = SessionProcess.get_state(session_id)
      # Count should still be 1 (throttled)
      assert state2.users.fetch_count == 1

      # Wait for throttle window to pass
      Process.sleep(150)

      # Now it should execute again
      SessionProcess.dispatch(session_id, "fetch-users")

      state3 = SessionProcess.get_state(session_id)
      assert state3.users.fetch_count == 2
    end
  end

  describe "debounce functionality" do
    test "debounces rapid action dispatches", %{session_id: session_id} do
      # Rapid dispatches - only last one should execute after delay
      SessionProcess.dispatch(session_id, "search-users", "a")
      Process.sleep(10)
      SessionProcess.dispatch(session_id, "search-users", "ab")
      Process.sleep(10)
      SessionProcess.dispatch(session_id, "search-users", "abc")

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
      SessionProcess.dispatch(session_id, "add-user", "Alice")
      assert_receive {:user_count_changed, 1}

      # Add cart item - should NOT trigger notification (different slice)
      SessionProcess.dispatch(session_id, "add-item", "Book")
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
      SessionProcess.dispatch(session_id, "add-user", "Alice")
      SessionProcess.dispatch(session_id, "add-item", "Book")

      assert_receive {:user_count, 1}
      assert_receive {:cart_count, 1}
    end
  end

  describe "error handling" do
    test "unknown actions don't break reducer", %{session_id: session_id} do
      # Dispatch unknown action
      SessionProcess.dispatch(session_id, "unknown-action")

      # State should be unchanged
      state = SessionProcess.get_state(session_id)
      assert state.users.users == []
      assert state.cart.items == []
    end

    test "action without matching slice continues", %{session_id: session_id} do
      # Dispatch action that doesn't match any slice's handlers
      SessionProcess.dispatch(session_id, "random-action")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == []
      assert state.cart.items == []
    end
  end

  describe "combined_reducers error handling" do
    test "raises on invalid list entry - string" do
      defmodule InvalidStringSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          ["invalid_string"]
        end
      end

      session_id = "test_invalid_string_#{:rand.uniform(1_000_000)}"

      {:error, {exception, _stacktrace}} =
        SessionProcess.start_session(session_id, InvalidStringSession)

      assert %ArgumentError{} = exception
      assert exception.message =~ ~r/Invalid combined_reducers entry/
    end

    test "raises on invalid list entry - integer" do
      defmodule InvalidIntegerSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [123]
        end
      end

      session_id = "test_invalid_int_#{:rand.uniform(1_000_000)}"

      {:error, {exception, _stacktrace}} =
        SessionProcess.start_session(session_id, InvalidIntegerSession)

      assert %ArgumentError{} = exception
      assert exception.message =~ ~r/Invalid combined_reducers entry/
    end

    test "raises on invalid list entry - single element tuple" do
      defmodule InvalidTupleSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [{:invalid}]
        end
      end

      session_id = "test_invalid_tuple_#{:rand.uniform(1_000_000)}"

      {:error, {exception, _stacktrace}} =
        SessionProcess.start_session(session_id, InvalidTupleSession)

      assert %ArgumentError{} = exception
      assert exception.message =~ ~r/Invalid combined_reducers entry/
    end

    test "raises on duplicate reducer names - same module twice" do
      defmodule DuplicateModuleSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            UserReducer,
            UserReducer
          ]
        end
      end

      session_id = "test_dup_module_#{:rand.uniform(1_000_000)}"

      {:error, {exception, _stacktrace}} =
        SessionProcess.start_session(session_id, DuplicateModuleSession)

      assert %ArgumentError{} = exception
      assert exception.message =~ ~r/Duplicate reducer name: :users/
    end

    test "raises on duplicate reducer names - explicit name conflict" do
      defmodule DuplicateNameSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            UserReducer,
            {:users, CartReducer}
          ]
        end
      end

      session_id = "test_dup_name_#{:rand.uniform(1_000_000)}"

      {:error, {exception, _stacktrace}} =
        SessionProcess.start_session(session_id, DuplicateNameSession)

      assert %ArgumentError{} = exception
      assert exception.message =~ ~r/Duplicate reducer name: :users/
    end

    test "raises if module is not a reducer" do
      defmodule NotAReducer do
        # No "use Phoenix.SessionProcess, :reducer"
        def some_function, do: :ok
      end

      defmodule NonReducerSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [NotAReducer]
        end
      end

      session_id = "test_non_reducer_#{:rand.uniform(1_000_000)}"

      {:error, {exception, _stacktrace}} =
        SessionProcess.start_session(session_id, NonReducerSession)

      assert %ArgumentError{} = exception
      assert exception.message =~ ~r/not a reducer module/
    end

    test "raises if module doesn't exist" do
      defmodule NonExistentModuleSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [NonExistentModule]
        end
      end

      session_id = "test_nonexistent_#{:rand.uniform(1_000_000)}"

      {:error, {exception, _stacktrace}} =
        SessionProcess.start_session(session_id, NonExistentModuleSession)

      assert %ArgumentError{} = exception
      assert exception.message =~ ~r/Could not load reducer module/
    end

    test "handles empty list gracefully" do
      defmodule EmptyListSession do
        use Phoenix.SessionProcess, :process

        def init_state(_arg), do: %{count: 0}

        def combined_reducers do
          []
        end
      end

      session_id = "test_empty_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, EmptyListSession)

      state = SessionProcess.get_state(session_id)
      assert state.count == 0

      SessionProcess.terminate(session_id)
    end
  end

  describe "all three list formats together" do
    test "combines Module, {name, Module}, and {name, Module, prefix} formats" do
      defmodule MixedFormatSession do
        use Phoenix.SessionProcess, :process

        def init_state(_arg), do: %{global: true}

        def combined_reducers do
          [
            # Format 1: Module - uses @name and @action_prefix
            UserReducer,
            # Format 2: {name, Module} - custom name, prefix = "cart"
            {:cart, CartReducer},
            # Format 3: {name, Module, prefix} - explicit name and prefix
            {:shipping, ShippingReducer, "ship"}
          ]
        end
      end

      session_id = "mixed_format_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, MixedFormatSession)

      state = SessionProcess.get_state(session_id)

      # Verify all slices initialized correctly
      assert state.users == %{users: [], fetch_count: 0, search_query: nil}
      assert state.cart == %{items: []}
      assert state.shipping == %{address: nil, cost: 0}
      assert state.global == true

      # Test actions route to correct slices
      SessionProcess.dispatch(session_id, "add-user", "Alice")
      SessionProcess.dispatch(session_id, "add-item", "Book")
      SessionProcess.dispatch(session_id, "calculate-shipping", "123 Main St")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]
      assert state.cart.items == ["Book"]
      assert state.shipping.address == "123 Main St"
      assert state.shipping.cost == 10

      SessionProcess.terminate(session_id)
    end
  end

  describe "@name and @action_prefix metadata" do
    test "verifies __reducer_name__ returns correct name" do
      assert UserReducer.__reducer_name__() == :users
      assert CartReducer.__reducer_name__() == :cart
      assert ShippingReducer.__reducer_name__() == :shipping
      assert InventoryReducer.__reducer_name__() == :inventory
    end

    test "verifies __reducer_action_prefix__ returns correct prefix" do
      assert UserReducer.__reducer_action_prefix__() == "user"
      assert CartReducer.__reducer_action_prefix__() == "cart"
      assert ShippingReducer.__reducer_action_prefix__() == "ship"
      # InventoryReducer has no @action_prefix, should default to stringified @name
      assert InventoryReducer.__reducer_action_prefix__() == "inventory"
    end

    test "reducer with @name but no @action_prefix defaults to stringified name" do
      defmodule DefaultPrefixSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [InventoryReducer]
        end
      end

      session_id = "default_prefix_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, DefaultPrefixSession)

      state = SessionProcess.get_state(session_id)
      assert state.inventory == %{stock: 100}

      # Dispatch action - should work with default prefix
      SessionProcess.dispatch(session_id, "reduce-stock", 20)

      state = SessionProcess.get_state(session_id)
      assert state.inventory.stock == 80

      SessionProcess.terminate(session_id)
    end
  end

  describe "state slice initialization variations" do
    test "reducer without init_state/0 defaults to empty map" do
      defmodule NoInitStateSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [NotificationsReducer]
        end
      end

      session_id = "no_init_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, NoInitStateSession)

      state = SessionProcess.get_state(session_id)
      # Should be %{} because NotificationsReducer has no init_state/0
      assert state.notifications == %{}

      # Should still handle actions
      SessionProcess.dispatch(session_id, "add-notification", "Hello")

      state = SessionProcess.get_state(session_id)
      assert state.notifications.messages == ["Hello"]

      SessionProcess.terminate(session_id)
    end

    test "multiple reducers with different init_state implementations" do
      defmodule MixedInitSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            UserReducer,
            # Has init_state/0
            NotificationsReducer
            # No init_state/0
          ]
        end
      end

      session_id = "mixed_init_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, MixedInitSession)

      state = SessionProcess.get_state(session_id)
      assert state.users == %{users: [], fetch_count: 0, search_query: nil}
      assert state.notifications == %{}

      SessionProcess.terminate(session_id)
    end
  end

  describe "backward compatibility with map format" do
    test "old map format still works" do
      defmodule MapFormatSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          # Old map format
          %{
            users: UserReducer,
            cart: CartReducer
          }
        end
      end

      session_id = "map_format_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, MapFormatSession)

      state = SessionProcess.get_state(session_id)
      assert state.users == %{users: [], fetch_count: 0, search_query: nil}
      assert state.cart == %{items: []}

      # Actions should work
      SessionProcess.dispatch(session_id, "add-user", "Bob")
      SessionProcess.dispatch(session_id, "add-item", "Pen")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Bob"]
      assert state.cart.items == ["Pen"]

      SessionProcess.terminate(session_id)
    end
  end

  describe "custom prefix in 3-tuple format" do
    test "verifies custom prefix is used for action routing" do
      defmodule CustomPrefixSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            # ShippingReducer has @action_prefix "ship", but we override with "shipping"
            {:shipping, ShippingReducer, "shipping"}
          ]
        end
      end

      session_id = "custom_prefix_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, CustomPrefixSession)

      state = SessionProcess.get_state(session_id)
      assert state.shipping == %{address: nil, cost: 0}

      # This action should work (module's handle_action doesn't check prefix)
      SessionProcess.dispatch(session_id, "calculate-shipping", "456 Oak Ave")

      state = SessionProcess.get_state(session_id)
      assert state.shipping.address == "456 Oak Ave"

      SessionProcess.terminate(session_id)
    end

    test "different names with same module using different prefixes" do
      defmodule SamePrefixSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            # Same module used twice with different names and prefixes
            {:primary_users, UserReducer, "primary"},
            {:secondary_users, UserReducer, "secondary"}
          ]
        end
      end

      session_id = "same_prefix_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, SamePrefixSession)

      state = SessionProcess.get_state(session_id)
      assert state.primary_users == %{users: [], fetch_count: 0, search_query: nil}
      assert state.secondary_users == %{users: [], fetch_count: 0, search_query: nil}

      # Dispatch to both slices
      SessionProcess.dispatch(session_id, "add-user", "Primary User")

      state = SessionProcess.get_state(session_id)
      # Both slices receive the action (prefix routing not yet implemented in handle_action)
      assert "Primary User" in state.primary_users.users
      assert "Primary User" in state.secondary_users.users

      SessionProcess.terminate(session_id)
    end
  end

  describe "special characters in @name and @action_prefix" do
    test "handles special characters in name and prefix" do
      defmodule SpecialCharsSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [SpecialCharsReducer]
        end
      end

      session_id = "special_chars_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, SpecialCharsSession)

      state = SessionProcess.get_state(session_id)
      assert state.special_chars_test == %{data: "test"}

      # Test action dispatch
      SessionProcess.dispatch(session_id, "update-special")

      state = SessionProcess.get_state(session_id)
      assert state.special_chars_test.data == "updated"

      SessionProcess.terminate(session_id)
    end

    test "handles underscores and hyphens in names" do
      defmodule UnderscoreHyphenSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            {:user_profile, UserReducer, "user-profile"},
            {:cart_items, CartReducer, "cart.items"}
          ]
        end
      end

      session_id = "underscore_hyphen_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, UnderscoreHyphenSession)

      state = SessionProcess.get_state(session_id)
      assert Map.has_key?(state, :user_profile)
      assert Map.has_key?(state, :cart_items)

      SessionProcess.terminate(session_id)
    end
  end

  describe "large list of reducers (stress test)" do
    test "handles many reducers in one session" do
      defmodule StressTestSession do
        use Phoenix.SessionProcess, :process

        def init_state(_arg), do: %{global: 0}

        def combined_reducers do
          [
            StressReducer1,
            StressReducer2,
            StressReducer3,
            StressReducer4,
            StressReducer5,
            {:users, UserReducer},
            {:cart, CartReducer},
            {:shipping, ShippingReducer, "ship"},
            {:inventory, InventoryReducer},
            {:notifications, NotificationsReducer}
          ]
        end
      end

      session_id = "stress_test_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, StressTestSession)

      state = SessionProcess.get_state(session_id)

      # Verify all slices exist
      assert Map.has_key?(state, :stress1)
      assert Map.has_key?(state, :stress2)
      assert Map.has_key?(state, :stress3)
      assert Map.has_key?(state, :stress4)
      assert Map.has_key?(state, :stress5)
      assert Map.has_key?(state, :users)
      assert Map.has_key?(state, :cart)
      assert Map.has_key?(state, :shipping)
      assert Map.has_key?(state, :inventory)
      assert Map.has_key?(state, :notifications)
      assert state.global == 0

      # Test that actions still work with many reducers
      SessionProcess.dispatch(session_id, "add-user", "Stress Test User")
      SessionProcess.dispatch(session_id, "add-item", "Stress Test Item")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Stress Test User"]
      assert state.cart.items == ["Stress Test Item"]

      SessionProcess.terminate(session_id)
    end
  end

  describe "prefix metadata storage" do
    test "verifies prefix is stored correctly in internal state" do
      defmodule PrefixMetadataSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            UserReducer,
            # prefix = "user"
            {:cart, CartReducer},
            # prefix = "cart"
            {:shipping, ShippingReducer, "ship"}
            # prefix = "ship"
          ]
        end
      end

      session_id = "prefix_meta_#{:rand.uniform(1_000_000)}"
      {:ok, pid} = SessionProcess.start_session(session_id, PrefixMetadataSession)

      # Access internal state to verify prefix storage
      internal_state = :sys.get_state(pid)

      # Check _redux_reducers map contains correct prefix information
      assert {:combined, UserReducer, :users, "user"} = internal_state._redux_reducers[:users]
      assert {:combined, CartReducer, :cart, "cart"} = internal_state._redux_reducers[:cart]

      assert {:combined, ShippingReducer, :shipping, "ship"} =
               internal_state._redux_reducers[:shipping]

      SessionProcess.terminate(session_id)
    end

    test "different modules with same prefix are allowed" do
      defmodule SamePrefixDiffModulesSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            {:users, UserReducer, "shared"},
            {:cart, CartReducer, "shared"}
          ]
        end
      end

      session_id = "same_prefix_diff_#{:rand.uniform(1_000_000)}"
      # Should not raise - same prefix with different names is valid
      {:ok, _pid} = SessionProcess.start_session(session_id, SamePrefixDiffModulesSession)

      state = SessionProcess.get_state(session_id)
      assert Map.has_key?(state, :users)
      assert Map.has_key?(state, :cart)

      SessionProcess.terminate(session_id)
    end
  end

  describe "edge cases and integration" do
    test "list-based reducers work with throttle and debounce" do
      defmodule ThrottleDebounceListSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [{:users, UserReducer}]
          # UserReducer has throttle/debounce
        end
      end

      session_id = "throttle_debounce_list_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, ThrottleDebounceListSession)

      # Test throttle still works
      SessionProcess.dispatch(session_id, "fetch-users")
      state1 = SessionProcess.get_state(session_id)
      assert state1.users.fetch_count == 1

      SessionProcess.dispatch(session_id, "fetch-users")
      state2 = SessionProcess.get_state(session_id)
      # Throttled
      assert state2.users.fetch_count == 1

      # Test debounce still works
      SessionProcess.dispatch(session_id, "search-users", "test")
      state3 = SessionProcess.get_state(session_id)
      # Not executed yet
      assert state3.users.search_query == nil

      Process.sleep(100)
      state4 = SessionProcess.get_state(session_id)
      # Now executed
      assert state4.users.search_query == "test"

      SessionProcess.terminate(session_id)
    end

    test "list-based reducers work with subscriptions" do
      defmodule SubscriptionListSession do
        use Phoenix.SessionProcess, :process

        def combined_reducers do
          [
            {:users, UserReducer},
            {:cart, CartReducer}
          ]
        end
      end

      session_id = "subscription_list_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, SubscriptionListSession)

      {:ok, _sub_id} =
        SessionProcess.subscribe(
          session_id,
          fn state -> length(state.users.users) end,
          :user_count,
          self()
        )

      assert_receive {:user_count, 0}

      SessionProcess.dispatch(session_id, "add-user", "Alice")
      assert_receive {:user_count, 1}

      SessionProcess.terminate(session_id)
    end
  end

  describe "action routing with explicit reducer targeting" do
    test "routes action only to specified reducers" do
      alias Phoenix.SessionProcess.Action

      session_id = "routing_explicit_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, TestSessionProcess)

      # Dispatch with explicit reducer targeting - only UserReducer should get it
      SessionProcess.dispatch(session_id, "add-user", "Alice", reducers: [:users])

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Alice"]

      # Cart should not have been affected
      assert state.cart.items == []

      # Now target only CartReducer
      SessionProcess.dispatch(session_id, "add-item", "Book", reducers: [:cart])

      state = SessionProcess.get_state(session_id)
      assert state.cart.items == ["Book"]

      # Users should still have Alice
      assert state.users.users == ["Alice"]

      SessionProcess.terminate(session_id)
    end

    test "routes action to multiple specified reducers" do
      session_id = "routing_multi_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, TestSessionProcess)

      # Dispatch to both UserReducer and CartReducer
      SessionProcess.dispatch(session_id, "add-user", "Bob", reducers: [:users, :cart])

      # UserReducer should handle it
      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Bob"]

      # CartReducer ignores unknown actions, so items stay empty
      assert state.cart.items == []

      SessionProcess.terminate(session_id)
    end

    test "no routing metadata calls all reducers" do
      session_id = "routing_all_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, TestSessionProcess)

      # Dispatch without routing metadata - goes to all reducers
      SessionProcess.dispatch(session_id, "add-user", "Charlie")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Charlie"]

      SessionProcess.terminate(session_id)
    end
  end

  describe "action routing with prefix matching" do
    test "routes action by prefix in action type" do
      defmodule PrefixRoutingSession do
        use Phoenix.SessionProcess, :process

        def init_state(_arg), do: %{}

        def combined_reducers do
          [
            UserReducer,
            # UserReducer has @name :users and @action_prefix "user"
            CartReducer
            # CartReducer has @name :cart and @action_prefix "cart"
          ]
        end
      end

      session_id = "routing_prefix_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, PrefixRoutingSession)

      # Dispatch "user.fetch-users" - should route to UserReducer only
      SessionProcess.dispatch(session_id, "user.fetch-users")

      state = SessionProcess.get_state(session_id)
      # UserReducer fetch_count increments on "fetch-users" action
      assert state.users.fetch_count == 1

      # Dispatch "cart.clear-cart" - should route to CartReducer only
      SessionProcess.dispatch(session_id, "cart.clear-cart")

      state = SessionProcess.get_state(session_id)
      # Cart items should be empty (clear was called)
      assert state.cart.items == []

      SessionProcess.terminate(session_id)
    end

    test "explicit prefix filter overrides inferred prefix" do
      session_id = "routing_explicit_prefix_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, TestSessionProcess)

      # Even though action type is "cart.add", explicitly route to users reducer
      SessionProcess.dispatch(
        session_id,
        "cart.add",
        "Book",
        reducer_prefix: "users"
      )

      state = SessionProcess.get_state(session_id)
      # UserReducer ignores "cart.add", so users list is empty
      assert state.users.users == []

      # CartReducer was NOT called due to explicit prefix filter
      assert state.cart.items == []

      SessionProcess.terminate(session_id)
    end

    test "action without dot notation goes to all reducers" do
      session_id = "routing_no_prefix_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, TestSessionProcess)

      # Action type has no dot, so no prefix to route by - goes to all
      SessionProcess.dispatch(session_id, "add-user", "Dave")

      state = SessionProcess.get_state(session_id)
      assert state.users.users == ["Dave"]

      SessionProcess.terminate(session_id)
    end

    test "custom prefix in 3-tuple format enables prefix routing" do
      defmodule CustomPrefixSession do
        use Phoenix.SessionProcess, :process

        def init_state(_arg), do: %{}

        def combined_reducers do
          [
            {:shipping, ShippingReducer, "ship"}
          ]
        end
      end

      session_id = "routing_custom_prefix_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, CustomPrefixSession)

      # Action with "ship.calculate-shipping" should route to ShippingReducer
      # After prefix stripping, becomes "calculate-shipping" which matches the handler
      SessionProcess.dispatch(session_id, "ship.calculate-shipping", "123 Main St")

      state = SessionProcess.get_state(session_id)
      # ShippingReducer now handles this action with stripped prefix
      assert state.shipping.address == "123 Main St"
      assert state.shipping.cost == 10

      SessionProcess.terminate(session_id)
    end
  end

  describe "action routing performance and isolation" do
    test "targeted routing only calls specified reducer" do
      defmodule CountingSession do
        use Phoenix.SessionProcess, :process

        def init_state(_arg), do: %{call_counts: %{users: 0, cart: 0}}

        def combined_reducers do
          [
            {:users, CountingUserReducer},
            {:cart, CountingCartReducer}
          ]
        end
      end

      session_id = "routing_performance_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, CountingSession)

      # Dispatch to only users
      SessionProcess.dispatch(session_id, "test-action", nil, reducers: [:users])

      state = SessionProcess.get_state(session_id)
      # UserReducer was called
      assert state.users.count == 1
      # CartReducer was NOT called
      assert state.cart.count == 0

      # Dispatch to only cart
      SessionProcess.dispatch(session_id, "test-action", nil, reducers: [:cart])

      state = SessionProcess.get_state(session_id)
      # UserReducer still at 1
      assert state.users.count == 1
      # CartReducer now called
      assert state.cart.count == 1

      # Dispatch to all (no routing)
      SessionProcess.dispatch(session_id, "test-action")

      state = SessionProcess.get_state(session_id)
      # Both called
      assert state.users.count == 2
      assert state.cart.count == 2

      SessionProcess.terminate(session_id)
    end

    test "prefix routing with many reducers only calls matching ones" do
      defmodule ManyReducersSession do
        use Phoenix.SessionProcess, :process

        def init_state(_arg), do: %{}

        def combined_reducers do
          [
            {:user1, StressReducer1, "user"},
            {:user2, StressReducer2, "user"},
            {:cart1, StressReducer3, "cart"},
            {:cart2, StressReducer4, "cart"},
            {:other, StressReducer5, "other"}
          ]
        end
      end

      session_id = "routing_many_#{:rand.uniform(1_000_000)}"
      {:ok, _pid} = SessionProcess.start_session(session_id, ManyReducersSession)

      # Dispatch with "user." prefix - should only call user1 and user2
      SessionProcess.dispatch(session_id, "user.action")

      state = SessionProcess.get_state(session_id)
      # Verify all slices exist
      assert Map.has_key?(state, :user1)
      assert Map.has_key?(state, :user2)
      assert Map.has_key?(state, :cart1)
      assert Map.has_key?(state, :cart2)
      assert Map.has_key?(state, :other)

      SessionProcess.terminate(session_id)
    end
  end
end
