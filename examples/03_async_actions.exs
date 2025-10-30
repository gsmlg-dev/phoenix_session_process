# Example 3: Async Actions with Cancellation (v1.0.0)
#
# This example demonstrates async action handling with cancellation callbacks.
# Run with: mix run examples/03_async_actions.exs

IO.puts("\n=== Example 3: Async Actions with Cancellation ===\n")

# Start the supervisor
{:ok, _} = Phoenix.SessionProcess.Supervisor.start_link([])

# Define a reducer with async action support
defmodule AsyncReducer do
  use Phoenix.SessionProcess, :reducer

  @name :data
  @action_prefix "data"

  def init_state do
    %{items: [], loading: false, error: nil}
  end

  def handle_action(action, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "data.loading"} ->
        %{state | loading: true, error: nil}

      %Action{type: "data.loaded", payload: items} ->
        %{state | items: items, loading: false}

      %Action{type: "data.error", payload: error} ->
        %{state | error: error, loading: false}

      %Action{type: "data.clear"} ->
        %{state | items: [], loading: false, error: nil}

      _ ->
        state
    end
  end

  # Handle async actions - MUST return cancellation callback
  def handle_async(action, dispatch, _state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "data.fetch", payload: delay_ms} ->
        # Start async task
        task =
          Task.async(fn ->
            # Simulate loading
            dispatch.("data.loading")
            Process.sleep(delay_ms)

            # Simulate fetching data
            items = ["item1", "item2", "item3"]
            dispatch.("data.loaded", items)
          end)

        # Return cancellation callback
        fn ->
          Task.shutdown(task, :brutal_kill)
          IO.puts("   🚫 Task cancelled")
          :ok
        end

      _ ->
        # Default: no-op cancellation
        fn -> nil end
    end
  end
end

# Define session process
defmodule AsyncSession do
  use Phoenix.SessionProcess, :process

  def init_state(_arg) do
    %{}
  end

  def combined_reducers do
    [AsyncReducer]
  end
end

# Create a session
session_id = "async_session_#{:rand.uniform(1_000_000)}"
IO.puts("1. Starting session...")
{:ok, _pid} = Phoenix.SessionProcess.start(session_id, AsyncSession)
IO.puts("   ✓ Session started: #{session_id}")

# Subscribe to loading state
IO.puts("\n2. Subscribing to state changes...")

{:ok, sub_id} =
  Phoenix.SessionProcess.subscribe(
    session_id,
    fn state -> {state.data.loading, length(state.data.items)} end,
    :state_changed
  )

# Receive initial value
receive do
  {:state_changed, {loading, count}} ->
    IO.puts("   • Initial state: loading=#{loading}, items=#{count}")
end

# Dispatch async action
IO.puts("\n3. Dispatching async fetch (1000ms delay)...")

{:ok, cancel_fn} =
  Phoenix.SessionProcess.dispatch_async(
    session_id,
    "data.fetch",
    1000,
    async: true
  )

IO.puts("   ✓ Async dispatch started")
IO.puts("   ✓ Received cancellation function")

# Receive loading notification
receive do
  {:state_changed, {loading, count}} ->
    IO.puts("   📬 State update: loading=#{loading}, items=#{count}")
after
  500 ->
    IO.puts("   ⚠️  No loading notification")
end

# Wait for completion
receive do
  {:state_changed, {loading, count}} ->
    IO.puts("   📬 State update: loading=#{loading}, items=#{count}")
after
  2000 ->
    IO.puts("   ⚠️  No completion notification")
end

# Test cancellation
IO.puts("\n4. Testing cancellation...")

{:ok, cancel_fn2} =
  Phoenix.SessionProcess.dispatch_async(
    session_id,
    "data.fetch",
    2000,
    async: true
  )

# Wait a bit
Process.sleep(100)

# Cancel the task
IO.puts("   • Calling cancellation function...")
:ok = cancel_fn2.()

# Should not receive completion
receive do
  {:state_changed, _} ->
    IO.puts("   ⚠️  Received notification (task might have completed before cancel)")
after
  1000 ->
    IO.puts("   ✓ No notification received (task was cancelled)")
end

# Get final state
IO.puts("\n5. Final state...")
state = Phoenix.SessionProcess.get_state(session_id)
IO.puts("   • Items: #{inspect(state.data.items)}")
IO.puts("   • Loading: #{state.data.loading}")

# Cleanup
:ok = Phoenix.SessionProcess.unsubscribe(session_id, sub_id)
:ok = Phoenix.SessionProcess.terminate(session_id)
IO.puts("\n6. Cleaned up")

IO.puts("\n=== Example Complete ===\n")
