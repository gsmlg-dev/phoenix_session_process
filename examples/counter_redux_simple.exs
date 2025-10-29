# Example: Counter with Redux-style state management
#
# Run with: mix run examples/counter_redux_simple.exs

# Start the supervisor
Phoenix.SessionProcess.Supervisor.start_link([])

defmodule CounterExample do
  @moduledoc """
  Example session process with Redux-style state management.
  """
  use Phoenix.SessionProcess, :process

  def user_init(_arg) do
    %{count: 0, history: []}
  end
end

# Create a unique session ID
session_id = "counter_session_#{:rand.uniform(1_000_000)}"

IO.puts("\n=== Phoenix.SessionProcess Redux Example ===\n")

# Start the session
IO.puts("1. Starting session...")
{:ok, _pid} = Phoenix.SessionProcess.start(session_id, CounterExample)
IO.puts("   ✓ Session started: #{session_id}")

# Register a reducer
IO.puts("\n2. Registering counter reducer...")

counter_reducer = fn action, state ->
  case action do
    :increment ->
      %{state | count: state.count + 1, history: [:increment | state.history]}

    :decrement ->
      %{state | count: state.count - 1, history: [:decrement | state.history]}

    {:set, value} ->
      %{state | count: value, history: [{:set, value} | state.history]}

    _ ->
      state
  end
end

:ok = Phoenix.SessionProcess.register_reducer(session_id, :counter, counter_reducer)
IO.puts("   ✓ Reducer registered")

# Subscribe to count changes
IO.puts("\n3. Subscribing to count changes...")

{:ok, sub_id} =
  Phoenix.SessionProcess.subscribe(
    session_id,
    fn state -> state.count end,
    :count_changed
  )

IO.puts("   ✓ Subscription created: #{inspect(sub_id)}")

# Receive initial value
receive do
  {:count_changed, initial_count} ->
    IO.puts("   ✓ Received initial count: #{initial_count}")
end

# Dispatch some actions
IO.puts("\n4. Dispatching actions...")

IO.puts("   • Dispatching :increment...")
{:ok, state1} = Phoenix.SessionProcess.dispatch(session_id, :increment)
IO.puts("     State: #{inspect(state1)}")

receive do
  {:count_changed, count} ->
    IO.puts("     📬 Received notification: count = #{count}")
end

IO.puts("   • Dispatching :increment...")
{:ok, state2} = Phoenix.SessionProcess.dispatch(session_id, :increment)
IO.puts("     State: #{inspect(state2)}")

receive do
  {:count_changed, count} ->
    IO.puts("     📬 Received notification: count = #{count}")
end

IO.puts("   • Dispatching {:set, 10}...")
{:ok, state3} = Phoenix.SessionProcess.dispatch(session_id, {:set, 10})
IO.puts("     State: #{inspect(state3)}")

receive do
  {:count_changed, count} ->
    IO.puts("     📬 Received notification: count = #{count}")
end

# Async dispatch
IO.puts("\n5. Testing async dispatch...")
IO.puts("   • Dispatching :increment (async)...")
:ok = Phoenix.SessionProcess.dispatch(session_id, :increment, async: true)

# Wait for notification
receive do
  {:count_changed, count} ->
    IO.puts("     📬 Received notification: count = #{count}")
after
  1000 ->
    IO.puts("     ⚠️  No notification received (timeout)")
end

# Register a named selector
IO.puts("\n6. Using named selectors...")
:ok = Phoenix.SessionProcess.register_selector(session_id, :count, fn s -> s.count end)
:ok = Phoenix.SessionProcess.register_selector(session_id, :history, fn s -> s.history end)

count = Phoenix.SessionProcess.select(session_id, :count)
IO.puts("   • Count (via selector): #{count}")

history = Phoenix.SessionProcess.select(session_id, :history)
IO.puts("   • History (via selector): #{inspect(Enum.reverse(history))}")

# Get state with inline selector
IO.puts("\n7. Getting state with inline selector...")
doubled_count = Phoenix.SessionProcess.get_state(session_id, fn s -> s.count * 2 end)
IO.puts("   • Doubled count: #{doubled_count}")

# Unsubscribe
IO.puts("\n8. Unsubscribing...")
:ok = Phoenix.SessionProcess.unsubscribe(session_id, sub_id)
IO.puts("   ✓ Unsubscribed")

# Dispatch after unsubscribe (should not receive notification)
IO.puts("   • Dispatching :increment after unsubscribe...")
{:ok, state4} = Phoenix.SessionProcess.dispatch(session_id, :increment)
IO.puts("     State: #{inspect(state4)}")

receive do
  {:count_changed, _count} ->
    IO.puts("     ⚠️  Received notification (should not happen!)")
after
  100 ->
    IO.puts("     ✓ No notification received (as expected)")
end

# Clean up
IO.puts("\n9. Cleaning up...")
:ok = Phoenix.SessionProcess.terminate(session_id)
IO.puts("   ✓ Session terminated")

IO.puts("\n=== Example Complete ===\n")
