# Redux-style State Management Example
# Run with: mix run examples/redux_example.exs

alias Phoenix.SessionProcess.Redux

IO.puts("🚀 Redux-style State Management Example")
IO.puts(String.duplicate("-", 50))

# 1. Basic Redux usage
IO.puts("\n1. Basic Redux Usage")
redux = Redux.init_state(%{count: 0, user: nil})
IO.inspect(Redux.current_state(redux), label: "Initial state")

# Define a simple reducer
reducer = fn state, action ->
  case action do
    {:increment, value} -> %{state | count: state.count + value}
    {:decrement, value} -> %{state | count: state.count - value}
    {:set_user, user} -> %{state | user: user}
    :reset -> %{count: 0, user: nil}
    _ -> state
  end
end

# Dispatch actions
redux = Redux.dispatch(redux, {:increment, 5}, reducer)
IO.inspect(Redux.current_state(redux), label: "After increment")

redux = Redux.dispatch(redux, {:set_user, %{name: "Alice", id: 1}}, reducer)
IO.inspect(Redux.current_state(redux), label: "After setting user")

redux = Redux.dispatch(redux, {:decrement, 2}, reducer)
IO.inspect(Redux.current_state(redux), label: "After decrement")

# 2. Time-travel debugging
IO.puts("\n2. Time-Travel Debugging")
redux = Redux.dispatch(redux, {:increment, 3}, reducer)
IO.inspect(length(Redux.history(redux)), label: "Action history length")

# Go back 2 steps
redux = Redux.time_travel(redux, 2)
IO.inspect(Redux.current_state(redux), label: "State after time travel")

# 3. Middleware example
IO.puts("\n3. Middleware Example")
logger_middleware = fn action, state, next ->
  IO.puts("[LOG] Action: #{inspect(action)}")
  IO.puts("[LOG] Before: #{inspect(state)}")
  new_state = next.(action)
  IO.puts("[LOG] After: #{inspect(new_state)}")
  new_state
end

redux_with_middleware = Redux.init_state(%{count: 0})
|> Redux.add_middleware(logger_middleware)

redux_with_middleware = Redux.dispatch(redux_with_middleware, {:increment, 10}, reducer)

# 4. Reset functionality
IO.puts("\n4. Reset Functionality")
redux = Redux.reset(redux)
IO.inspect(Redux.current_state(redux), label: "State after reset")

IO.puts("\n✅ Redux example completed successfully!")