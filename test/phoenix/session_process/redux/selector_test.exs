defmodule Phoenix.SessionProcess.Redux.SelectorTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess.Redux
  alias Phoenix.SessionProcess.Redux.Selector

  setup do
    # Clear selector cache before each test
    Selector.clear_cache()

    # Create a sample Redux state
    redux =
      Redux.init_state(%{
        user: %{id: 1, name: "Alice", email: "alice@example.com"},
        items: [
          %{id: 1, name: "Widget", price: 10, category: "tools"},
          %{id: 2, name: "Gadget", price: 20, category: "tools"},
          %{id: 3, name: "Book", price: 15, category: "media"}
        ],
        filter: "tools",
        count: 0
      })

    {:ok, redux: redux}
  end

  describe "select/2 with simple selectors" do
    test "selects user from state", %{redux: redux} do
      selector = fn state -> state.user end
      result = Selector.select(redux, selector)

      assert result == %{id: 1, name: "Alice", email: "alice@example.com"}
    end

    test "selects nested value from state", %{redux: redux} do
      selector = fn state -> state.user.name end
      result = Selector.select(redux, selector)

      assert result == "Alice"
    end

    test "selects array from state", %{redux: redux} do
      selector = fn state -> state.items end
      result = Selector.select(redux, selector)

      assert length(result) == 3
      assert Enum.at(result, 0).name == "Widget"
    end
  end

  describe "create_selector/2 with memoization" do
    test "creates a memoized selector", %{redux: redux} do
      selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items -> length(items) end
        )

      assert is_map(selector)
      assert Map.has_key?(selector, :deps)
      assert Map.has_key?(selector, :compute)
      assert Map.has_key?(selector, :cache_key)
    end

    test "computes derived state from single dependency", %{redux: redux} do
      selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items -> length(items) end
        )

      result = Selector.select(redux, selector)
      assert result == 3
    end

    test "computes derived state from multiple dependencies", %{redux: redux} do
      selector =
        Selector.create_selector(
          [
            fn state -> state.items end,
            fn state -> state.filter end
          ],
          fn items, filter ->
            Enum.filter(items, fn item -> item.category == filter end)
          end
        )

      result = Selector.select(redux, selector)
      assert length(result) == 2
      assert Enum.all?(result, &(&1.category == "tools"))
    end

    test "memoizes results for same inputs", %{redux: redux} do
      # Create selector with side effect to track calls
      call_count = :counters.new(1, [])

      selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items ->
            :counters.add(call_count, 1, 1)
            length(items)
          end
        )

      # First call - should compute
      result1 = Selector.select(redux, selector)
      assert result1 == 3
      assert :counters.get(call_count, 1) == 1

      # Second call with same state - should use cache
      result2 = Selector.select(redux, selector)
      assert result2 == 3
      # No additional computation
      assert :counters.get(call_count, 1) == 1
    end

    test "recomputes when inputs change", %{redux: redux} do
      call_count = :counters.new(1, [])

      selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items ->
            :counters.add(call_count, 1, 1)
            length(items)
          end
        )

      # First call
      result1 = Selector.select(redux, selector)
      assert result1 == 3
      assert :counters.get(call_count, 1) == 1

      # Update state with different items
      new_redux = %{redux | current_state: %{redux.current_state | items: []}}

      # Should recompute because items changed
      result2 = Selector.select(new_redux, selector)
      assert result2 == 0
      # Recomputed
      assert :counters.get(call_count, 1) == 2
    end

    test "validates compute function arity matches dependencies" do
      assert_raise ArgumentError, ~r/arity.*does not match/, fn ->
        Selector.create_selector(
          [fn state -> state.items end, fn state -> state.filter end],
          # Takes 1 arg but should take 2
          fn items -> length(items) end
        )
      end
    end
  end

  describe "composed selectors" do
    test "composes multiple selector levels", %{redux: redux} do
      # Level 1: Select items
      items_selector = fn state -> state.items end

      # Level 2: Filter items
      filtered_selector =
        Selector.create_selector(
          [items_selector, fn state -> state.filter end],
          fn items, filter ->
            Enum.filter(items, &(&1.category == filter))
          end
        )

      # Level 3: Calculate total price
      total_selector =
        Selector.create_selector(
          [filtered_selector],
          fn filtered_items ->
            Enum.reduce(filtered_items, 0, &(&1.price + &2))
          end
        )

      result = Selector.select(redux, total_selector)
      # Widget (10) + Gadget (20)
      assert result == 30
    end

    test "complex composition with multiple branches", %{redux: redux} do
      user_name_selector = fn state -> state.user.name end

      item_count_selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items -> length(items) end
        )

      summary_selector =
        Selector.create_selector(
          [user_name_selector, item_count_selector],
          fn name, count ->
            "#{name} has #{count} items"
          end
        )

      result = Selector.select(redux, summary_selector)
      assert result == "Alice has 3 items"
    end
  end

  describe "cache management" do
    test "clear_cache/0 clears all cached values" do
      selector =
        Selector.create_selector(
          [fn state -> state.count end],
          fn count -> count * 2 end
        )

      redux = Redux.init_state(%{count: 5})

      # Compute once
      result1 = Selector.select(redux, selector)
      assert result1 == 10

      # Check cache has data
      stats = Selector.cache_stats()
      assert stats.entries > 0

      # Clear cache
      Selector.clear_cache()

      # Verify cache is empty
      stats = Selector.cache_stats()
      assert stats.entries == 0
      assert stats.selectors == 0
    end

    test "clear_selector_cache/1 clears specific selector", %{redux: redux} do
      selector1 =
        Selector.create_selector(
          [fn state -> state.count end],
          fn count -> count * 2 end
        )

      selector2 =
        Selector.create_selector(
          [fn state -> state.count end],
          fn count -> count * 3 end
        )

      # Use both selectors
      Selector.select(redux, selector1)
      Selector.select(redux, selector2)

      # Clear only selector1
      Selector.clear_selector_cache(selector1)

      # Both should still work
      assert Selector.select(redux, selector1) == 0
      assert Selector.select(redux, selector2) == 0
    end

    test "cache_stats/0 returns accurate statistics", %{redux: redux} do
      selector1 =
        Selector.create_selector(
          [fn state -> state.count end],
          fn count -> count + 1 end
        )

      selector2 =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items -> length(items) end
        )

      # Initial stats
      stats = Selector.cache_stats()
      assert stats.entries == 0
      assert stats.selectors == 0

      # Use selectors
      Selector.select(redux, selector1)
      Selector.select(redux, selector2)

      # Check stats
      stats = Selector.cache_stats()
      assert stats.entries == 2
      assert stats.selectors == 2
    end
  end

  describe "performance characteristics" do
    test "cache provides performance benefit for expensive computations" do
      expensive_selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items ->
            # Simulate expensive computation
            :timer.sleep(10)
            Enum.map(items, & &1.price) |> Enum.sum()
          end
        )

      redux = Redux.init_state(%{items: [%{price: 10}, %{price: 20}, %{price: 30}]})

      # First call - should be slow
      {time1, result1} = :timer.tc(fn -> Selector.select(redux, expensive_selector) end)
      assert result1 == 60
      # At least 10ms
      assert time1 > 10_000

      # Second call - should be fast (cached)
      {time2, result2} = :timer.tc(fn -> Selector.select(redux, expensive_selector) end)
      assert result2 == 60
      # Should be much faster
      assert time2 < time1 / 2
    end

    test "handles large number of selectors efficiently", %{redux: redux} do
      # Create 100 selectors
      selectors =
        for i <- 1..100 do
          Selector.create_selector(
            [fn state -> state.count end],
            fn count -> count + i end
          )
        end

      # Execute all selectors
      results = Enum.map(selectors, &Selector.select(redux, &1))

      # Verify all computed correctly
      assert length(results) == 100
      # 0 + 1
      assert Enum.at(results, 0) == 1
      # 0 + 100
      assert Enum.at(results, 99) == 100

      # Check cache stats
      stats = Selector.cache_stats()
      assert stats.entries == 100
      assert stats.selectors == 100
    end
  end

  describe "edge cases" do
    test "handles nil values in state" do
      redux = Redux.init_state(%{user: nil, items: []})

      selector =
        Selector.create_selector(
          [fn state -> state.user end],
          fn user -> if user, do: user.name, else: "Guest" end
        )

      result = Selector.select(redux, selector)
      assert result == "Guest"
    end

    test "handles empty arrays" do
      redux = Redux.init_state(%{items: []})

      selector =
        Selector.create_selector(
          [fn state -> state.items end],
          fn items -> Enum.count(items) end
        )

      result = Selector.select(redux, selector)
      assert result == 0
    end

    test "handles complex nested structures" do
      redux =
        Redux.init_state(%{
          data: %{
            deeply: %{
              nested: %{
                value: [1, 2, 3]
              }
            }
          }
        })

      selector =
        Selector.create_selector(
          [fn state -> state.data.deeply.nested.value end],
          fn values -> Enum.sum(values) end
        )

      result = Selector.select(redux, selector)
      assert result == 6
    end

    test "different selectors with same cache key don't interfere" do
      redux = Redux.init_state(%{a: 1, b: 2})

      selector1 =
        Selector.create_selector(
          [fn state -> state.a end],
          fn a -> a * 2 end
        )

      selector2 =
        Selector.create_selector(
          [fn state -> state.a end],
          fn a -> a * 3 end
        )

      result1 = Selector.select(redux, selector1)
      result2 = Selector.select(redux, selector2)

      assert result1 == 2
      assert result2 == 3
    end
  end

  describe "selector isolation across processes" do
    test "cache is isolated per process" do
      selector =
        Selector.create_selector(
          [fn state -> state.count end],
          fn count -> count * 2 end
        )

      redux = Redux.init_state(%{count: 5})

      # Compute in main process
      result_main = Selector.select(redux, selector)
      assert result_main == 10

      # Check cache in main process
      stats_main = Selector.cache_stats()
      assert stats_main.entries == 1

      # Spawn new process and check cache is empty
      task =
        Task.async(fn ->
          stats_task = Selector.cache_stats()
          result_task = Selector.select(redux, selector)
          {stats_task, result_task}
        end)

      {stats_task, result_task} = Task.await(task)

      # Task should have empty cache initially
      assert stats_task.entries == 0

      # But computation should still work
      assert result_task == 10

      # Main process cache should be unchanged
      stats_main_after = Selector.cache_stats()
      assert stats_main_after.entries == 1
    end
  end
end
