# Example 1: Basic Session Process
#
# This example demonstrates basic session management without Redux.
# Run with: mix run examples/01_basic_session.exs

IO.puts("\n=== Example 1: Basic Session Process ===\n")

# Start the supervisor
{:ok, _} = Phoenix.SessionProcess.Supervisor.start_link([])

# Define a simple session process
defmodule BasicSession do
  use Phoenix.SessionProcess, :process

  @impl true
  def init(_arg) do
    {:ok, %{visits: 0, data: %{}}}
  end

  @impl true
  def handle_call(:get_visits, _from, state) do
    {:reply, state.visits, state}
  end

  @impl true
  def handle_call({:get_data, key}, _from, state) do
    {:reply, Map.get(state.data, key), state}
  end

  @impl true
  def handle_cast(:increment_visits, state) do
    {:noreply, %{state | visits: state.visits + 1}}
  end

  @impl true
  def handle_cast({:store_data, key, value}, state) do
    {:noreply, %{state | data: Map.put(state.data, key, value)}}
  end
end

# Create a session
session_id = "session_#{:rand.uniform(1_000_000)}"
IO.puts("1. Starting session...")
{:ok, pid} = Phoenix.SessionProcess.start_session(session_id, BasicSession)
IO.puts("   ✓ Session started: #{session_id}")
IO.puts("   ✓ Process PID: #{inspect(pid)}")

# Use call (synchronous)
IO.puts("\n2. Using synchronous calls...")
visits = Phoenix.SessionProcess.call(session_id, :get_visits)
IO.puts("   • Initial visits: #{visits}")

# Use cast (asynchronous)
IO.puts("\n3. Using asynchronous casts...")
:ok = Phoenix.SessionProcess.cast(session_id, :increment_visits)
:ok = Phoenix.SessionProcess.cast(session_id, :increment_visits)
:ok = Phoenix.SessionProcess.cast(session_id, {:store_data, :user_name, "Alice"})
# Wait for casts to process
Process.sleep(10)

# Get updated state
visits = Phoenix.SessionProcess.call(session_id, :get_visits)
IO.puts("   • Visits after increments: #{visits}")

name = Phoenix.SessionProcess.call(session_id, {:get_data, :user_name})
IO.puts("   • Stored user name: #{name}")

# Check if session is running
IO.puts("\n4. Session status...")
running = Phoenix.SessionProcess.started?(session_id)
IO.puts("   • Session running: #{running}")

# List all sessions
sessions = Phoenix.SessionProcess.list_session()
IO.puts("   • Active sessions: #{length(sessions)}")

# Terminate session
IO.puts("\n5. Terminating session...")
:ok = Phoenix.SessionProcess.terminate(session_id)
IO.puts("   ✓ Session terminated")

running = Phoenix.SessionProcess.started?(session_id)
IO.puts("   • Session running: #{running}")

IO.puts("\n=== Example Complete ===\n")
