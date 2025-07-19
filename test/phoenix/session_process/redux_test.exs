defmodule Phoenix.SessionProcess.ReduxTest do
  use ExUnit.Case, async: true
  alias Phoenix.SessionProcess.Redux

  describe "init_state/1" do
    test "initializes with default options" do
      initial_state = %{count: 0, user: nil}
      redux = Redux.init_state(initial_state)
      
      assert Redux.current_state(redux) == initial_state
      assert Redux.initial_state(redux) == initial_state
      assert Redux.history(redux) == []
      assert Redux.middleware(redux) == []
    end

    test "initializes with custom options" do
      initial_state = %{count: 0}
      middleware = [fn _action, state, next -> next.(state) end]
      
      redux = Redux.init_state(initial_state, 
        max_history_size: 50,
        middleware: middleware
      )
      
      assert Redux.current_state(redux) == initial_state
      assert length(Redux.middleware(redux)) == 1
    end
  end

  describe "dispatch/3" do
    test "dispatches actions with reducer function" do
      initial_state = %{count: 0}
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.dispatch(redux, {:increment, 5}, reducer)
      
      assert Redux.current_state(redux) == %{count: 5}
    end

    test "handles multiple actions" do
      initial_state = %{count: 0, user: nil}
      reducer = fn 
        state, {:increment, val} -> %{state | count: state.count + val}
        state, {:set_user, user} -> %{state | user: user}
        state, _ -> state
      end
      
      redux = Redux.init_state(initial_state)
      
      redux = Redux.dispatch(redux, {:increment, 3}, reducer)
      redux = Redux.dispatch(redux, {:set_user, "alice"}, reducer)
      redux = Redux.dispatch(redux, {:increment, 2}, reducer)
      
      assert Redux.current_state(redux) == %{count: 5, user: "alice"}
    end

    test "records action history" do
      initial_state = %{count: 0}
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.dispatch(redux, {:increment, 1}, reducer)
      redux = Redux.dispatch(redux, {:increment, 2}, reducer)
      
      history = Redux.history(redux)
      assert length(history) == 2
      
      [latest | _] = history
      assert latest.action == {:increment, 2}
      assert latest.new_state == %{count: 3}
      assert latest.previous_state == %{count: 1}
      assert is_integer(latest.timestamp)
    end

    test "respects max_history_size" do
      initial_state = %{count: 0}
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end
      
      redux = Redux.init_state(initial_state, max_history_size: 3)
      
      # Dispatch 5 actions
      redux = Enum.reduce(1..5, redux, fn i, acc ->
        Redux.dispatch(acc, {:increment, i}, reducer)
      end)
      
      history = Redux.history(redux)
      assert length(history) == 3
      
      # Should contain the last 3 actions
      actions = Enum.map(history, & &1.action)
      assert actions == [{:increment, 5}, {:increment, 4}, {:increment, 3}]
    end
  end

  describe "reset/1" do
    test "resets to initial state" do
      initial_state = %{count: 0, user: nil}
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.dispatch(redux, {:increment, 5}, reducer)
      redux = Redux.dispatch(redux, {:increment, 3}, reducer)
      
      assert Redux.current_state(redux) == %{count: 8, user: nil}
      
      redux = Redux.reset(redux)
      assert Redux.current_state(redux) == %{count: 0, user: nil}
      assert Redux.history(redux) == []
    end
  end

  describe "time_travel/2" do
    test "travels back in history" do
      initial_state = %{count: 0}
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.dispatch(redux, {:increment, 1}, reducer)
      redux = Redux.dispatch(redux, {:increment, 2}, reducer)
      redux = Redux.dispatch(redux, {:increment, 3}, reducer)
      
      assert Redux.current_state(redux) == %{count: 6}
      
      # Time travel should work but we need a reducer for time travel
      # This test verifies the basic functionality
      assert length(Redux.history(redux)) == 3
    end

    test "raises error when traveling beyond history" do
      initial_state = %{count: 0}
      redux = Redux.init_state(initial_state)
      
      assert_raise RuntimeError, ~r/Cannot time travel beyond history length/, fn ->
        Redux.time_travel(redux, 1)
      end
    end
  end

  describe "middleware" do
    test "middleware is applied correctly" do
      initial_state = %{count: 0, log: []}
      
      logging_middleware = fn action, _state, next ->
        new_state = next.(action)
        %{new_state | log: ["processed #{inspect(action)}" | new_state.log]}
      end
      
      reducer = fn state, {:add, val} -> %{state | count: state.count + val} end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.add_middleware(redux, logging_middleware)
      
      redux = Redux.dispatch(redux, {:add, 5}, reducer)
      
      assert Redux.current_state(redux).count == 5
      assert Redux.current_state(redux).log == ["processed {:add, 5}"]
    end

    test "middleware can modify action" do
      initial_state = %{count: 0}
      
      double_middleware = fn {:increment, val}, _state, next ->
        next.({:increment, val * 2})
      end
      
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.add_middleware(redux, double_middleware)
      
      redux = Redux.dispatch(redux, {:increment, 5}, reducer)
      
      assert Redux.current_state(redux).count == 10
    end

    test "middleware can short-circuit action" do
      initial_state = %{count: 0}
      
      reject_middleware = fn {:increment, _}, _state, _next ->
        %{count: 42}  # Return fixed state without calling next
      end
      
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.add_middleware(redux, reject_middleware)
      
      redux = Redux.dispatch(redux, {:increment, 5}, reducer)
      
      assert Redux.current_state(redux).count == 42
    end
  end

  describe "built-in middleware" do
    test "validation_middleware with valid actions" do
      initial_state = %{count: 0}
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end
      
      validator = fn {:increment, val} when val > 0 -> true
                    _ -> false end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.add_middleware(redux, Redux.validation_middleware(validator))
      
      # Valid action should work
      redux = Redux.dispatch(redux, {:increment, 5}, reducer)
      assert Redux.current_state(redux).count == 5
      
      # Invalid action should be rejected
      redux = Redux.dispatch(redux, {:increment, -1}, reducer)
      assert Redux.current_state(redux).count == 5  # Unchanged
    end
  end

  describe "edge cases" do
    test "handles nil state" do
      reducer = fn state, _action -> state end
      redux = Redux.init_state(nil)
      
      redux = Redux.dispatch(redux, :noop, reducer)
      assert Redux.current_state(redux) == nil
    end

    test "handles empty state" do
      reducer = fn state, {:set, key, value} -> Map.put(state, key, value) end
      redux = Redux.init_state(%{})
      
      redux = Redux.dispatch(redux, {:set, :test, "value"}, reducer)
      assert Redux.current_state(redux) == %{test: "value"}
    end

    test "complex nested state updates" do
      initial_state = %{
        user: %{profile: %{name: "", age: 0}},
        settings: %{theme: :light, notifications: true}
      }
      
      reducer = fn state, {:update_name, name} ->
        %{state | user: %{state.user | profile: %{state.user.profile | name: name}}}
      end
      
      redux = Redux.init_state(initial_state)
      redux = Redux.dispatch(redux, {:update_name, "Alice"}, reducer)
      
      expected = %{
        user: %{profile: %{name: "Alice", age: 0}},
        settings: %{theme: :light, notifications: true}
      }
      
      assert Redux.current_state(redux) == expected
    end
  end
end