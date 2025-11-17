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

  @impl true
  def init_state do
    %{items: [], loading: false, error: nil}
  end

  @impl true
  def handle_action(action, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "loading"} ->
        %{state | loading: true, error: nil}

      %Action{type: "loaded", payload: items} ->
        %{state | items: items, loading: false}

      %Action{type: "error", payload: error} ->
        %{state | error: error, loading: false}

      %Action{type: "clear"} ->
        %{state | items: [], loading: false, error: nil}

      _ ->
        state
    end
  end

  # Handle async actions - MUST return cancellation callback
  @impl true
  def handle_async(action, dispatch, _state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "fetch", payload: delay_ms} ->
        # Start async task
        task =
          Task.async(fn ->
            # Simulate loading
            dispatch.("data.loading", nil, [])
            Process.sleep(delay_ms)

            # Simulate fetching data
            items = ["item1", "item2", "item3"]
            dispatch.("data.loaded", items, [])
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
{:ok, _pid} = Phoenix.SessionProcess.start_session(session_id, AsyncSession)
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

# Dispatch async action (dispatch_async automatically adds async: true)
IO.puts("\n3. Dispatching async fetch (1000ms delay)...")

:ok = Phoenix.SessionProcess.dispatch_async(session_id, "data.fetch", 1000)

IO.puts("   ✓ Async dispatch started (fire-and-forget)")

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

:ok = Phoenix.SessionProcess.dispatch_async(session_id, "data.fetch", 50)

IO.puts("   • dispatch_async returns :ok (fire-and-forget)")
IO.puts("   • Cancellation is handled internally by handle_async/3 callback")
IO.puts("   • The cancel function is for internal lifecycle management only")

# Wait for completion
Process.sleep(100)

receive do
  {:state_changed, {loading, count}} ->
    IO.puts("   ✓ Received notification: loading=#{loading}, items=#{count}")
after
  200 ->
    IO.puts("   • No notification (already processed)")
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
