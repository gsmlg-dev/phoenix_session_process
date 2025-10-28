defmodule Phoenix.SessionProcess.Redux.SubscriptionTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess.Redux
  alias Phoenix.SessionProcess.Redux.Selector
  alias Phoenix.SessionProcess.Redux.Subscription

  setup do
    redux =
      Redux.init_state(%{
        user: %{id: 1, name: "Alice"},
        count: 0,
        items: []
      })

    {:ok, redux: redux}
  end

  describe "subscribe_to_struct/3 without selector" do
    test "creates subscription and calls callback immediately", %{redux: redux} do
      # Use send to track callback
      test_pid = self()

      {new_redux, sub_id} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state -> send(test_pid, {:callback, state}) end
        )

      # Should receive immediate callback with current state
      assert_receive {:callback, state}
      assert state.user.name == "Alice"
      assert state.count == 0

      # Verify subscription was added
      assert is_reference(sub_id)
      assert length(new_redux.subscriptions) == 1
    end

    test "notifies on every state change", %{redux: redux} do
      test_pid = self()

      {redux, _sub_id} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state -> send(test_pid, {:state_change, state.count}) end
        )

      # Clear initial callback
      assert_receive {:state_change, 0}

      # Update state
      redux = %{redux | current_state: %{redux.current_state | count: 1}}
      redux = Subscription.notify_all_struct(redux)

      # Should receive notification
      assert_receive {:state_change, 1}

      # Update again
      redux = %{redux | current_state: %{redux.current_state | count: 2}}
      redux = Subscription.notify_all_struct(redux)

      # Should receive another notification
      assert_receive {:state_change, 2}
    end

    test "supports multiple subscriptions", %{redux: redux} do
      test_pid = self()

      {redux, _sub1} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state -> send(test_pid, {:sub1, state.count}) end
        )

      {redux, _sub2} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state -> send(test_pid, {:sub2, state.count * 2}) end
        )

      # Clear initial callbacks
      assert_receive {:sub1, 0}
      assert_receive {:sub2, 0}

      # Update state
      redux = %{redux | current_state: %{redux.current_state | count: 5}}
      _redux = Subscription.notify_all_struct(redux)

      # Both should be notified
      assert_receive {:sub1, 5}
      assert_receive {:sub2, 10}
    end
  end

  describe "subscribe_to_struct/3 with simple selector" do
    test "only notifies when selected value changes", %{redux: redux} do
      test_pid = self()
      user_selector = fn state -> state.user end

      {redux, _sub_id} =
        Subscription.subscribe_to_struct(
          redux,
          user_selector,
          fn user -> send(test_pid, {:user_changed, user}) end
        )

      # Clear initial callback
      assert_receive {:user_changed, %{id: 1, name: "Alice"}}

      # Update count (user unchanged)
      redux = %{redux | current_state: %{redux.current_state | count: 5}}
      redux = Subscription.notify_all_struct(redux)

      # Should NOT receive notification
      refute_receive {:user_changed, _}, 100

      # Update user
      new_user = %{id: 2, name: "Bob"}
      redux = %{redux | current_state: %{redux.current_state | user: new_user}}
      _redux = Subscription.notify_all_struct(redux)

      # Should receive notification
      assert_receive {:user_changed, ^new_user}
    end

    test "uses shallow equality for change detection", %{redux: redux} do
      test_pid = self()
      items_selector = fn state -> state.items end

      {redux, _sub_id} =
        Subscription.subscribe_to_struct(
          redux,
          items_selector,
          fn items -> send(test_pid, {:items_changed, length(items)}) end
        )

      # Clear initial callback
      assert_receive {:items_changed, 0}

      # Update with same empty list (different reference but same value)
      redux = %{redux | current_state: %{redux.current_state | items: []}}
      redux = Subscription.notify_all_struct(redux)

      # Should NOT notify (same value)
      refute_receive {:items_changed, _}, 100

      # Update with different list
      redux = %{redux | current_state: %{redux.current_state | items: [1, 2, 3]}}
      _redux = Subscription.notify_all_struct(redux)

      # Should notify
      assert_receive {:items_changed, 3}
    end

    test "nested selector extracts specific value", %{redux: redux} do
      test_pid = self()
      name_selector = fn state -> state.user.name end

      {redux, _sub_id} =
        Subscription.subscribe_to_struct(
          redux,
          name_selector,
          fn name -> send(test_pid, {:name_changed, name}) end
        )

      # Clear initial callback
      assert_receive {:name_changed, "Alice"}

      # Update user.id (name unchanged)
      new_user = %{redux.current_state.user | id: 999}
      redux = %{redux | current_state: %{redux.current_state | user: new_user}}
      redux = Subscription.notify_all_struct(redux)

      # Should NOT notify (name didn't change)
      refute_receive {:name_changed, _}, 100

      # Update user.name
      new_user = %{redux.current_state.user | name: "Charlie"}
      redux = %{redux | current_state: %{redux.current_state | user: new_user}}
      _redux = Subscription.notify_all_struct(redux)

      # Should notify
      assert_receive {:name_changed, "Charlie"}
    end
  end

  describe "subscribe_to_struct/3 with composed selector" do
    test "notifies only when computed value changes", %{redux: redux} do
      test_pid = self()

      # Selector that counts items matching a filter
      items_count_selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items -> length(items) end
        )

      {redux, _sub_id} =
        Subscription.subscribe_to_struct(
          redux,
          items_count_selector,
          fn count -> send(test_pid, {:count_changed, count}) end
        )

      # Clear initial callback
      assert_receive {:count_changed, 0}

      # Add items one by one
      redux = %{redux | current_state: %{redux.current_state | items: [1]}}
      redux = Subscription.notify_all_struct(redux)
      assert_receive {:count_changed, 1}

      redux = %{redux | current_state: %{redux.current_state | items: [1, 2]}}
      redux = Subscription.notify_all_struct(redux)
      assert_receive {:count_changed, 2}

      # Update user (items unchanged)
      redux = %{redux | current_state: %{redux.current_state | user: %{id: 99, name: "Test"}}}
      redux = Subscription.notify_all_struct(redux)

      # Should NOT notify (item count didn't change)
      refute_receive {:count_changed, _}, 100
    end

    test "works with multi-dependency selectors", %{redux: redux} do
      test_pid = self()

      redux =
        Redux.init_state(%{
          items: [
            %{name: "A", category: "tools", price: 10},
            %{name: "B", category: "media", price: 20},
            %{name: "C", category: "tools", price: 30}
          ],
          filter: "tools"
        })

      # Selector that filters and sums
      filtered_total_selector =
        Selector.create_selector(
          [
            fn state -> state.items end,
            fn state -> state.filter end
          ],
          fn items, filter ->
            items
            |> Enum.filter(&(&1.category == filter))
            |> Enum.map(& &1.price)
            |> Enum.sum()
          end
        )

      {redux, _sub_id} =
        Subscription.subscribe_to_struct(
          redux,
          filtered_total_selector,
          fn total -> send(test_pid, {:total_changed, total}) end
        )

      # Clear initial callback (10 + 30 = 40)
      assert_receive {:total_changed, 40}

      # Change filter to "media"
      redux = %{redux | current_state: %{redux.current_state | filter: "media"}}
      redux = Subscription.notify_all_struct(redux)

      # Should notify with new total (20)
      assert_receive {:total_changed, 20}

      # Change filter back to "tools"
      redux = %{redux | current_state: %{redux.current_state | filter: "tools"}}
      _redux = Subscription.notify_all_struct(redux)

      # Should notify (40 again)
      assert_receive {:total_changed, 40}
    end
  end

  describe "unsubscribe_from_struct/2" do
    test "removes subscription and stops notifications", %{redux: redux} do
      test_pid = self()

      {redux, sub_id} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state -> send(test_pid, {:notification, state.count}) end
        )

      # Clear initial callback
      assert_receive {:notification, 0}

      # Update state - should notify
      redux = %{redux | current_state: %{redux.current_state | count: 1}}
      redux = Subscription.notify_all_struct(redux)
      assert_receive {:notification, 1}

      # Unsubscribe
      redux = Subscription.unsubscribe_from_struct(redux, sub_id)
      assert Enum.empty?(redux.subscriptions)

      # Update state - should NOT notify
      redux = %{redux | current_state: %{redux.current_state | count: 2}}
      _redux = Subscription.notify_all_struct(redux)
      refute_receive {:notification, _}, 100
    end

    test "removes only specified subscription", %{redux: redux} do
      test_pid = self()

      {redux, sub1} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state -> send(test_pid, {:sub1, state.count}) end
        )

      {redux, _sub2} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state -> send(test_pid, {:sub2, state.count}) end
        )

      # Clear initial callbacks
      assert_receive {:sub1, 0}
      assert_receive {:sub2, 0}

      # Unsubscribe only sub1
      redux = Subscription.unsubscribe_from_struct(redux, sub1)
      assert length(redux.subscriptions) == 1

      # Update state
      redux = %{redux | current_state: %{redux.current_state | count: 5}}
      _redux = Subscription.notify_all_struct(redux)

      # Only sub2 should be notified
      refute_receive {:sub1, _}, 100
      assert_receive {:sub2, 5}
    end
  end

  describe "list_subscriptions/1" do
    test "returns all subscriptions", %{redux: redux} do
      # Initially empty
      assert Subscription.list_subscriptions(redux) == []

      # Add subscriptions
      {redux, _} = Subscription.subscribe_to_struct(redux, nil, fn _ -> :ok end)
      {redux, _} = Subscription.subscribe_to_struct(redux, nil, fn _ -> :ok end)

      subs = Subscription.list_subscriptions(redux)
      assert length(subs) == 2
    end

    test "subscriptions contain expected fields", %{redux: redux} do
      selector = fn state -> state.user end
      callback = fn _ -> :ok end

      {redux, sub_id} = Subscription.subscribe_to_struct(redux, selector, callback)

      [sub] = Subscription.list_subscriptions(redux)

      assert sub.id == sub_id
      assert is_function(sub.selector, 1)
      assert is_function(sub.callback, 1)
      assert Map.has_key?(sub, :last_value)
    end
  end

  describe "clear_all_struct/1" do
    test "removes all subscriptions", %{redux: redux} do
      {redux, _} = Subscription.subscribe_to_struct(redux, nil, fn _ -> :ok end)
      {redux, _} = Subscription.subscribe_to_struct(redux, nil, fn _ -> :ok end)
      {redux, _} = Subscription.subscribe_to_struct(redux, nil, fn _ -> :ok end)

      assert length(redux.subscriptions) == 3

      redux = Subscription.clear_all_struct(redux)
      assert redux.subscriptions == []
    end
  end

  describe "error handling in callbacks" do
    test "handles callback errors gracefully", %{redux: redux} do
      test_pid = self()

      # Callback that raises error
      {redux, _} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state ->
            if state.count > 0 do
              raise "Test error"
            else
              send(test_pid, {:callback_ok, state.count})
            end
          end
        )

      # Clear initial callback (count = 0, no error)
      assert_receive {:callback_ok, 0}

      # Update state to trigger error
      redux = %{redux | current_state: %{redux.current_state | count: 1}}

      # Should not crash, just log error
      redux = Subscription.notify_all_struct(redux)

      # Redux should still be usable
      assert redux.current_state.count == 1
    end

    test "one failing callback doesn't affect others", %{redux: redux} do
      test_pid = self()

      # First callback - raises error
      {redux, _} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn _state -> raise "Error in first callback" end
        )

      # Second callback - works fine
      {redux, _} =
        Subscription.subscribe_to_struct(
          redux,
          nil,
          fn state -> send(test_pid, {:second_callback, state.count}) end
        )

      # Clear initial callbacks
      assert_receive {:second_callback, 0}

      # Update state
      redux = %{redux | current_state: %{redux.current_state | count: 5}}
      _redux = Subscription.notify_all_struct(redux)

      # Second callback should still work
      assert_receive {:second_callback, 5}
    end
  end

  describe "integration with Redux.dispatch" do
    test "subscriptions are notified after dispatch", %{redux: redux} do
      test_pid = self()

      # Add subscription
      redux =
        Redux.subscribe(redux, fn state ->
          send(test_pid, {:state_updated, state.count})
        end)

      # Clear initial callback
      assert_receive {:state_updated, 0}

      # Dispatch action
      redux =
        Redux.dispatch(redux, :increment, fn state, :increment ->
          %{state | count: state.count + 1}
        end)

      # Should receive notification
      assert_receive {:state_updated, 1}

      # Verify state updated
      assert Redux.get_state(redux).count == 1
    end

    test "multiple subscriptions notified in order", %{redux: redux} do
      test_pid = self()

      redux =
        Redux.subscribe(redux, fn state ->
          send(test_pid, {:sub1, state.count})
        end)

      redux =
        Redux.subscribe(redux, fn state ->
          send(test_pid, {:sub2, state.count})
        end)

      redux =
        Redux.subscribe(redux, fn state ->
          send(test_pid, {:sub3, state.count})
        end)

      # Clear initial callbacks
      assert_receive {:sub1, 0}
      assert_receive {:sub2, 0}
      assert_receive {:sub3, 0}

      # Dispatch
      _redux =
        Redux.dispatch(redux, {:set_count, 5}, fn state, {:set_count, n} ->
          %{state | count: n}
        end)

      # All should be notified
      # Note: Order might not be guaranteed but all should arrive
      receive do
        msg1 -> assert msg1 in [{:sub1, 5}, {:sub2, 5}, {:sub3, 5}]
      end

      receive do
        msg2 -> assert msg2 in [{:sub1, 5}, {:sub2, 5}, {:sub3, 5}]
      end

      receive do
        msg3 -> assert msg3 in [{:sub1, 5}, {:sub2, 5}, {:sub3, 5}]
      end
    end
  end

  describe "performance" do
    test "handles many subscriptions efficiently", %{redux: redux} do
      # Add 100 subscriptions
      redux =
        Enum.reduce(1..100, redux, fn i, acc_redux ->
          {new_redux, _} =
            Subscription.subscribe_to_struct(
              acc_redux,
              nil,
              fn _state -> :ok end
            )

          new_redux
        end)

      assert length(redux.subscriptions) == 100

      # Notify all - should complete quickly
      {time, _} =
        :timer.tc(fn ->
          Subscription.notify_all_struct(redux)
        end)

      # Should complete in reasonable time (< 100ms for 100 subscriptions)
      assert time < 100_000
    end

    test "selector memoization benefits subscriptions", %{redux: redux} do
      call_count = :counters.new(1, [])

      # Expensive selector
      expensive_selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items ->
            :counters.add(call_count, 1, 1)
            # Simulate expensive computation
            :timer.sleep(1)
            length(items)
          end
        )

      {redux, _} =
        Subscription.subscribe_to_struct(
          redux,
          expensive_selector,
          fn _count -> :ok end
        )

      # Initial computation
      assert :counters.get(call_count, 1) == 1

      # Update unrelated field
      redux = %{redux | current_state: %{redux.current_state | user: %{id: 99, name: "Test"}}}
      redux = Subscription.notify_all_struct(redux)

      # Should not recompute (same items value)
      assert :counters.get(call_count, 1) == 1

      # Update items
      redux = %{redux | current_state: %{redux.current_state | items: [1, 2, 3]}}
      _redux = Subscription.notify_all_struct(redux)

      # Should recompute (items changed)
      assert :counters.get(call_count, 1) == 2
    end
  end
end
