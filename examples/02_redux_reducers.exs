# Example 2: Redux Store with Reducers (v1.0.0)
#
# This example demonstrates the Redux Store API with named reducers.
# Actions MUST use binary types in v1.0.0.
# Run with: mix run examples/02_redux_reducers.exs

IO.puts("\n=== Example 2: Redux Store with Reducers (v1.0.0) ===\n")

# Start the supervisor
{:ok, _} = Phoenix.SessionProcess.Supervisor.start_link([])

# Define a counter reducer
defmodule CounterReducer do
  use Phoenix.SessionProcess, :reducer

  @name :counter
  @action_prefix "counter"

  def init_state do
    %{count: 0}
  end

  def handle_action(action, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "increment"} ->
        %{state | count: state.count + 1}

      %Action{type: "decrement"} ->
        %{state | count: state.count - 1}

      %Action{type: "set", payload: value} ->
        %{state | count: value}

      _ ->
        state
    end
  end
end

# Define a user reducer
defmodule UserReducer do
  use Phoenix.SessionProcess, :reducer

  @name :user
  @action_prefix "user"

  def init_state do
    %{current_user: nil, logged_in: false}
  end

  def handle_action(action, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "login", payload: user} ->
        %{state | current_user: user, logged_in: true}

      %Action{type: "logout"} ->
        %{state | current_user: nil, logged_in: false}

      _ ->
        state
    end
  end
end

# Define session process with combined reducers
defmodule ReduxSession do
  use Phoenix.SessionProcess, :process

  def init_state(_arg) do
    %{}
  end

  def combined_reducers do
    [CounterReducer, UserReducer]
  end
end

# Create a session
session_id = "redux_session_#{:rand.uniform(1_000_000)}"
IO.puts("1. Starting session with combined reducers...")
{:ok, _pid} = Phoenix.SessionProcess.start(session_id, ReduxSession)
IO.puts("   ✓ Session started: #{session_id}")
IO.puts("   ✓ Reducers registered: counter, user")

# Get initial state
IO.puts("\n2. Initial state...")
state = Phoenix.SessionProcess.get_state(session_id)
IO.puts("   • State: #{inspect(state)}")

# Dispatch actions (MUST use binary types)
IO.puts("\n3. Dispatching counter actions...")
:ok = Phoenix.SessionProcess.dispatch(session_id, "counter.increment")
:ok = Phoenix.SessionProcess.dispatch(session_id, "counter.increment")
:ok = Phoenix.SessionProcess.dispatch(session_id, "counter.increment")
Process.sleep(10)

state = Phoenix.SessionProcess.get_state(session_id)
IO.puts("   • Count after 3 increments: #{state.counter.count}")

:ok = Phoenix.SessionProcess.dispatch(session_id, "counter.set", 10)
Process.sleep(10)

state = Phoenix.SessionProcess.get_state(session_id)
IO.puts("   • Count after set to 10: #{state.counter.count}")

# Dispatch user actions
IO.puts("\n4. Dispatching user actions...")
:ok = Phoenix.SessionProcess.dispatch(session_id, "user.login", %{id: 1, name: "Alice"})
Process.sleep(10)

state = Phoenix.SessionProcess.get_state(session_id)
IO.puts("   • User logged in: #{inspect(state.user.current_user)}")
IO.puts("   • Logged in status: #{state.user.logged_in}")

# Use selectors to get specific values
IO.puts("\n5. Using selectors...")
count = Phoenix.SessionProcess.get_state(session_id, fn s -> s.counter.count end)
IO.puts("   • Count (client-side selector): #{count}")

user_name =
  Phoenix.SessionProcess.get_state(session_id, fn s ->
    if s.user.current_user, do: s.user.current_user.name, else: nil
  end)

IO.puts("   • User name: #{user_name}")

# Server-side selection (more efficient for large states)
IO.puts("\n6. Server-side selection...")
server_count = Phoenix.SessionProcess.select_state(session_id, fn s -> s.counter.count end)
IO.puts("   • Count (server-side): #{server_count}")

# Subscribe to state changes
IO.puts("\n7. Subscribing to counter changes...")

{:ok, sub_id} =
  Phoenix.SessionProcess.subscribe(
    session_id,
    fn state -> state.counter.count end,
    :count_changed
  )

# Receive initial value
receive do
  {:count_changed, initial} ->
    IO.puts("   • Received initial count: #{initial}")
end

# Dispatch and receive notification
:ok = Phoenix.SessionProcess.dispatch(session_id, "counter.increment")

receive do
  {:count_changed, new_count} ->
    IO.puts("   • Received count update: #{new_count}")
after
  1000 ->
    IO.puts("   ⚠️  No notification (timeout)")
end

# Unsubscribe
:ok = Phoenix.SessionProcess.unsubscribe(session_id, sub_id)
IO.puts("   ✓ Unsubscribed")

# Cleanup
IO.puts("\n8. Cleaning up...")
:ok = Phoenix.SessionProcess.terminate(session_id)
IO.puts("   ✓ Session terminated")

IO.puts("\n=== Example Complete ===\n")
