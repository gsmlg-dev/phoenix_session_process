defmodule Phoenix.SessionProcess.ReduxIntegrationTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess.Redux
  alias Phoenix.SessionProcess.Redux.Selector
  alias Phoenix.SessionProcess.Redux.Subscription

  setup do
    # Clear selector cache before each test
    Selector.clear_cache()
    :ok
  end

  describe "Redux with subscriptions and selectors" do
    test "full workflow: init -> subscribe -> dispatch -> notify" do
      test_pid = self()

      # Initialize Redux with shopping cart state
      redux =
        Redux.init_state(%{
          user: nil,
          cart: [],
          total: 0
        })

      # Create selector for cart total
      cart_total_selector =
        Selector.create_selector(
          [fn state -> state.cart end],
          fn cart ->
            Enum.reduce(cart, 0, fn item, acc -> acc + item.price end)
          end
        )

      # Subscribe to cart total changes
      redux =
        Redux.subscribe(redux, cart_total_selector, fn total ->
          send(test_pid, {:total_changed, total})
        end)

      # Clear initial notification
      assert_receive {:total_changed, 0}

      # Dispatch: Set user
      redux =
        Redux.dispatch(redux, {:set_user, "Alice"}, fn state, {:set_user, name} ->
          %{state | user: name}
        end)

      # Should NOT notify (total unchanged)
      refute_receive {:total_changed, _}, 100

      # Dispatch: Add item to cart
      redux =
        Redux.dispatch(redux, {:add_item, %{name: "Widget", price: 10}}, fn state,
                                                                            {:add_item, item} ->
          %{state | cart: [item | state.cart]}
        end)

      # Should notify with new total
      assert_receive {:total_changed, 10}

      # Dispatch: Add another item
      redux =
        Redux.dispatch(redux, {:add_item, %{name: "Gadget", price: 20}}, fn state,
                                                                            {:add_item, item} ->
          %{state | cart: [item | state.cart]}
        end)

      # Should notify with updated total
      assert_receive {:total_changed, 30}

      # Verify final state
      final_state = Redux.get_state(redux)
      assert final_state.user == "Alice"
      assert length(final_state.cart) == 2
    end

    test "multiple subscriptions with different selectors" do
      test_pid = self()

      redux =
        Redux.init_state(%{
          user: %{name: "Alice", email: "alice@example.com"},
          items: [],
          filter: "all"
        })

      # Subscribe to user name
      name_selector = fn state -> state.user.name end

      redux =
        Redux.subscribe(redux, name_selector, fn name ->
          send(test_pid, {:name_changed, name})
        end)

      # Subscribe to item count
      count_selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items -> length(items) end
        )

      redux =
        Redux.subscribe(redux, count_selector, fn count ->
          send(test_pid, {:count_changed, count})
        end)

      # Subscribe to filtered items
      filtered_selector =
        Selector.create_selector(
          [
            fn state -> state.items end,
            fn state -> state.filter end
          ],
          fn items, filter ->
            if filter == "all" do
              items
            else
              Enum.filter(items, &(&1.type == filter))
            end
          end
        )

      redux =
        Redux.subscribe(redux, filtered_selector, fn items ->
          send(test_pid, {:filtered_changed, length(items)})
        end)

      # Clear initial notifications
      assert_receive {:name_changed, "Alice"}
      assert_receive {:count_changed, 0}
      assert_receive {:filtered_changed, 0}

      # Update user email (name unchanged)
      redux =
        Redux.dispatch(redux, {:set_email, "new@example.com"}, fn state, {:set_email, email} ->
          %{state | user: %{state.user | email: email}}
        end)

      # Only name selector should NOT notify
      refute_receive {:name_changed, _}, 100
      refute_receive {:count_changed, _}, 100
      refute_receive {:filtered_changed, _}, 100

      # Add item
      new_item = %{id: 1, name: "Tool", type: "hardware"}

      redux =
        Redux.dispatch(redux, {:add_item, new_item}, fn state, {:add_item, item} ->
          %{state | items: [item | state.items]}
        end)

      # Count and filtered should notify
      refute_receive {:name_changed, _}, 100
      assert_receive {:count_changed, 1}
      assert_receive {:filtered_changed, 1}
    end

    test "composed selectors with subscriptions" do
      test_pid = self()

      redux =
        Redux.init_state(%{
          products: [
            %{id: 1, name: "A", category: "tools", price: 10, inStock: true},
            %{id: 2, name: "B", category: "media", price: 20, inStock: false},
            %{id: 3, name: "C", category: "tools", price: 30, inStock: true}
          ],
          selectedCategory: "tools",
          showOnlyInStock: true
        })

      # Base selector: filter by category
      category_filtered =
        Selector.create_selector(
          [
            fn state -> state.products end,
            fn state -> state.selectedCategory end
          ],
          fn products, category ->
            Enum.filter(products, &(&1.category == category))
          end
        )

      # Composed selector: further filter by stock
      final_products =
        Selector.create_selector(
          [
            category_filtered,
            fn state -> state.showOnlyInStock end
          ],
          fn filtered, only_in_stock ->
            if only_in_stock do
              Enum.filter(filtered, & &1.inStock)
            else
              filtered
            end
          end
        )

      # Subscribe to final result
      redux =
        Redux.subscribe(redux, final_products, fn products ->
          send(test_pid, {:products_changed, Enum.map(products, & &1.id)})
        end)

      # Initial: should get [1, 3] (tools, in stock)
      assert_receive {:products_changed, [1, 3]}

      # Change to show all products
      redux =
        Redux.dispatch(redux, :show_all, fn state, :show_all ->
          %{state | showOnlyInStock: false}
        end)

      # Should NOT get notification - value is still [1, 3] (both tools are in stock)
      # Subscriptions use shallow equality, so no change = no notification
      refute_receive {:products_changed, _}, 100

      # Change category to "media"
      redux =
        Redux.dispatch(redux, :select_media, fn state, :select_media ->
          %{state | selectedCategory: "media"}
        end)

      # Should get [2] (media products, showOnlyInStock is false now)
      assert_receive {:products_changed, [2]}

      # Turn on stock filter
      _redux =
        Redux.dispatch(redux, :only_in_stock, fn state, :only_in_stock ->
          %{state | showOnlyInStock: true}
        end)

      # Should get [] (media product 2 is out of stock)
      assert_receive {:products_changed, []}
    end
  end

  describe "Redux history with subscriptions" do
    test "subscriptions work with time travel", _context do
      test_pid = self()

      # Define reducer
      reducer = fn state, action ->
        case action do
          :inc -> %{state | count: state.count + 1}
          _ -> state
        end
      end

      redux = Redux.init_state(%{count: 0}, max_history_size: 10, reducer: reducer)

      # Subscribe to count
      redux =
        Redux.subscribe(redux, fn state -> state.count end, fn count ->
          send(test_pid, {:count_notification, count})
        end)

      # Clear initial
      assert_receive {:count_notification, 0}

      # Dispatch several increments using stored reducer
      redux = Redux.dispatch(redux, :inc, reducer)
      assert_receive {:count_notification, 1}

      redux = Redux.dispatch(redux, :inc, reducer)
      assert_receive {:count_notification, 2}

      redux = Redux.dispatch(redux, :inc, reducer)
      assert_receive {:count_notification, 3}

      # Time travel back 2 steps
      redux = Redux.time_travel(redux, 2)

      # Should notify with count = 1
      assert_receive {:count_notification, 1}

      # Verify state
      assert Redux.get_state(redux).count == 1
    end
  end

  describe "Redux with middleware and subscriptions" do
    test "middleware doesn't interfere with subscriptions" do
      test_pid = self()

      # Logger middleware
      logger_middleware = fn action, _state, next ->
        send(test_pid, {:middleware_before, action})
        result = next.(action)
        send(test_pid, {:middleware_after, result})
        result
      end

      redux = Redux.init_state(%{count: 0})
      redux = Redux.add_middleware(redux, logger_middleware)

      # Add subscription
      redux =
        Redux.subscribe(redux, fn state -> state.count end, fn count ->
          send(test_pid, {:subscription, count})
        end)

      # Clear initial subscription
      assert_receive {:subscription, 0}

      # Dispatch
      _redux =
        Redux.dispatch(redux, :inc, fn state, :inc ->
          %{state | count: state.count + 1}
        end)

      # Should receive middleware messages
      assert_receive {:middleware_before, :inc}
      assert_receive {:middleware_after, %{count: 1}}

      # Should receive subscription notification
      assert_receive {:subscription, 1}
    end
  end

  describe "Performance under load" do
    test "many subscriptions with selectors perform well" do
      # Create complex state
      redux =
        Redux.init_state(%{
          users: Enum.map(1..100, fn i -> %{id: i, name: "User#{i}", score: i * 10} end),
          filter: 50
        })

      # Create 50 different selectors and subscriptions
      redux =
        Enum.reduce(1..50, redux, fn i, acc_redux ->
          selector =
            Selector.create_selector(
              [
                fn state -> state.users end,
                fn state -> state.filter end
              ],
              fn users, filter ->
                users
                |> Enum.filter(&(&1.score > filter * i))
                |> length()
              end
            )

          Redux.subscribe(acc_redux, selector, fn _count -> :ok end)
        end)

      # Measure dispatch time
      {time, _} =
        :timer.tc(fn ->
          Redux.dispatch(redux, :update_filter, fn state, :update_filter ->
            %{state | filter: 75}
          end)
        end)

      # Should complete in reasonable time (< 500ms)
      assert time < 500_000
    end

    test "selector cache improves repeated notifications" do
      call_count = :counters.new(1, [])

      expensive_selector =
        Selector.create_selector(
          [fn state -> state.value end],
          fn value ->
            :counters.add(call_count, 1, 1)
            # Simulate expensive computation
            :timer.sleep(5)
            value * 2
          end
        )

      redux = Redux.init_state(%{value: 1, other: 0})
      redux = Redux.subscribe(redux, expensive_selector, fn _v -> :ok end)

      # Initial computation
      assert :counters.get(call_count, 1) == 1

      # Update unrelated field 10 times
      redux =
        Enum.reduce(1..10, redux, fn i, acc ->
          Redux.dispatch(acc, {:set_other, i}, fn state, {:set_other, n} ->
            %{state | other: n}
          end)
        end)

      # Selector should not recompute (value unchanged)
      assert :counters.get(call_count, 1) == 1

      # Update value
      _redux =
        Redux.dispatch(redux, :update_value, fn state, :update_value ->
          %{state | value: 2}
        end)

      # Should recompute once
      assert :counters.get(call_count, 1) == 2
    end
  end

  describe "Error recovery" do
    test "Redux continues working after subscription callback error" do
      test_pid = self()

      redux = Redux.init_state(%{count: 0})

      # Add failing subscription
      redux =
        Redux.subscribe(redux, fn _state ->
          raise "Subscription error!"
        end)

      # Add working subscription
      redux =
        Redux.subscribe(redux, fn state ->
          send(test_pid, {:working, state.count})
        end)

      # Clear initial notification from working subscription
      assert_receive {:working, 0}

      # Dispatch - should not crash despite error
      redux =
        Redux.dispatch(redux, :inc, fn state, :inc ->
          %{state | count: state.count + 1}
        end)

      # Working subscription should still work
      assert_receive {:working, 1}

      # Redux should be functional
      assert Redux.get_state(redux).count == 1
    end

    test "invalid selector doesn't break subscription" do
      test_pid = self()

      redux = Redux.init_state(%{count: 0})

      # Selector that might fail
      risky_selector = fn state ->
        if state.count > 5 do
          # Will fail
          state.nonexistent_field.value
        else
          state.count
        end
      end

      # This should not crash when subscribing
      redux =
        Redux.subscribe(redux, risky_selector, fn value ->
          send(test_pid, {:value, value})
        end)

      # Initial should work
      assert_receive {:value, 0}

      # Increment to 3 - should work
      redux =
        Redux.dispatch(redux, :inc3, fn state, :inc3 ->
          %{state | count: 3}
        end)

      assert_receive {:value, 3}

      # Increment to 10 - selector will fail but shouldn't crash
      redux =
        Redux.dispatch(redux, :inc10, fn state, :inc10 ->
          %{state | count: 10}
        end)

      # Might not get notification due to error, but Redux should still work
      assert Redux.get_state(redux).count == 10
    end
  end

  describe "Subscription cleanup" do
    test "unsubscribe prevents future notifications" do
      test_pid = self()

      redux = Redux.init_state(%{count: 0})

      {redux, sub_id} =
        Subscription.subscribe_to_struct(redux, nil, fn state ->
          send(test_pid, {:notification, state.count})
        end)

      # Clear initial
      assert_receive {:notification, 0}

      # Dispatch - should notify
      redux =
        Redux.dispatch(redux, :inc, fn state, :inc ->
          %{state | count: state.count + 1}
        end)

      assert_receive {:notification, 1}

      # Unsubscribe using Redux.unsubscribe
      redux = Redux.unsubscribe(redux, sub_id)

      # Dispatch - should NOT notify
      _redux =
        Redux.dispatch(redux, :inc, fn state, :inc ->
          %{state | count: state.count + 1}
        end)

      refute_receive {:notification, _}, 100
    end

    test "clear all subscriptions" do
      test_pid = self()

      redux = Redux.init_state(%{count: 0})

      # Add multiple subscriptions
      redux = Redux.subscribe(redux, fn state -> send(test_pid, {:sub1, state.count}) end)
      redux = Redux.subscribe(redux, fn state -> send(test_pid, {:sub2, state.count}) end)
      redux = Redux.subscribe(redux, fn state -> send(test_pid, {:sub3, state.count}) end)

      # Clear initial notifications
      assert_receive {:sub1, 0}
      assert_receive {:sub2, 0}
      assert_receive {:sub3, 0}

      # Clear all subscriptions
      redux = Subscription.clear_all_struct(redux)

      # Dispatch - no notifications
      _redux =
        Redux.dispatch(redux, :inc, fn state, :inc ->
          %{state | count: state.count + 1}
        end)

      refute_receive {:sub1, _}, 100
      refute_receive {:sub2, _}, 100
      refute_receive {:sub3, _}, 100
    end
  end
end
