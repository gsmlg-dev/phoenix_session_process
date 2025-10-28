defmodule Phoenix.SessionProcess.Cleanup do
  @moduledoc """
  Automatic session cleanup process with TTL (Time-To-Live) support.

  This GenServer runs in the background and periodically cleans up expired session
  processes based on their last activity time. This prevents memory leaks from abandoned
  sessions and ensures efficient resource utilization.

  ## How It Works

  ### Cleanup Strategy
  - Runs cleanup tasks every 60 seconds (`@cleanup_interval`)
  - Checks all active session processes for expiration
  - Terminates sessions that have exceeded their TTL
  - Emits telemetry events for monitoring cleanup operations

  ### TTL Calculation
  Each session process tracks its last activity timestamp. The cleanup process:
  1. Gets the configured TTL from `Phoenix.SessionProcess.Config.session_ttl()`
  2. Calculates the expiration threshold (current_time - TTL)
  3. Compares each session's last activity against the threshold
  4. Terminates sessions that have been inactive longer than TTL

  ## Configuration

  The cleanup process respects the TTL configuration:

      config :phoenix_session_process,
        session_ttl: :timer.hours(2)  # Sessions expire after 2 hours

  ## Performance Considerations

  ### Memory Efficiency
  - Prevents memory accumulation from abandoned sessions
  - Releases resources back to the system
  - Maintains optimal memory usage patterns

  ### Performance Impact
  - Cleanup runs in the background without blocking requests
  - Uses efficient registry operations for session discovery
  - Minimal impact on active session performance

  ### Scalability
  - Handles thousands of concurrent sessions efficiently
  - Cleanup time scales linearly with active session count
  - Can be tuned for different deployment scales

  ## Telemetry

  The cleanup process emits several telemetry events:

  - `[:phoenix, :session_process, :cleanup]` - Cleanup cycle completed
  - `[:phoenix, :session_process, :cleanup_error]` - Cleanup operation failed
  - `[:phoenix, :session_process, :session_expired]` - Individual session expired

  ## Monitoring

  You can monitor cleanup performance through telemetry events.
  See the Telemetry section above for available events.

  Example handler setup is documented in the telemetry module.

  ## Error Handling

  - Session process termination failures are logged but don't stop cleanup
  - Registry lookup errors are handled gracefully
  - Continuous operation ensures consistent cleanup performance

  ## Integration

  This process is automatically started by the top-level supervisor and requires
  no manual intervention or configuration beyond setting the desired TTL.
  """
  use GenServer
  require Logger

  alias Phoenix.SessionProcess.{ActivityTracker, Config, Helpers, ProcessSupervisor, Telemetry}

  # 1 minute
  @cleanup_interval 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Initialize activity tracker
    ActivityTracker.init()
    schedule_cleanup()
    {:ok, %{timers: %{}}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_sessions()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info({:cleanup_session, session_id}, state) do
    # Check if session is actually expired (might have been refreshed)
    if ActivityTracker.expired?(session_id) and ProcessSupervisor.session_process_started?(session_id) do
      session_pid = ProcessSupervisor.session_process_pid(session_id)

      Telemetry.emit_auto_cleanup_event(
        session_id,
        Helpers.get_session_module(session_pid),
        session_pid
      )

      Phoenix.SessionProcess.terminate(session_id)
      ActivityTracker.remove(session_id)
    end

    # Remove timer reference
    new_state = %{state | timers: Map.delete(state.timers, session_id)}
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:store_timer, session_id, timer_ref}, _from, state) do
    # Cancel old timer if exists
    case Map.get(state.timers, session_id) do
      nil -> :ok
      old_ref -> Process.cancel_timer(old_ref)
    end

    new_timers = Map.put(state.timers, session_id, timer_ref)
    {:reply, :ok, %{state | timers: new_timers}}
  end

  @impl true
  def handle_call({:cancel_timer, session_id}, _from, state) do
    case Map.pop(state.timers, session_id) do
      {nil, _} ->
        {:reply, :ok, state}

      {timer_ref, new_timers} ->
        Process.cancel_timer(timer_ref)
        ActivityTracker.remove(session_id)
        {:reply, :ok, %{state | timers: new_timers}}
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired_sessions do
    start_time = System.monotonic_time()
    ttl = Config.session_ttl()

    # Check all active sessions for expiration
    all_sessions = Phoenix.SessionProcess.list_session()

    expired_count =
      all_sessions
      |> Enum.filter(fn {session_id, _pid} ->
        ActivityTracker.expired?(session_id, ttl: ttl)
      end)
      |> Enum.map(fn {session_id, pid} ->
        Logger.debug("Cleanup: Terminating expired session #{session_id}")

        Telemetry.emit_auto_cleanup_event(
          session_id,
          Helpers.get_session_module(pid),
          pid
        )

        Phoenix.SessionProcess.terminate(session_id)
        ActivityTracker.remove(session_id)

        session_id
      end)
      |> length()

    duration = System.monotonic_time() - start_time

    if expired_count > 0 do
      Logger.info("Cleanup: Removed #{expired_count} expired sessions in #{duration}µs")
    end

    :ok
  end

  @doc """
  Schedules cleanup for a specific session after TTL.
  Returns timer reference for potential cancellation.
  """
  @spec schedule_session_cleanup(binary()) :: reference()
  def schedule_session_cleanup(session_id) do
    ttl = Config.session_ttl()
    timer_ref = Process.send_after(__MODULE__, {:cleanup_session, session_id}, ttl)
    GenServer.call(__MODULE__, {:store_timer, session_id, timer_ref})

    # Record initial activity
    ActivityTracker.touch(session_id)

    timer_ref
  end

  @doc """
  Cancels scheduled cleanup for a session.
  """
  @spec cancel_session_cleanup(binary()) :: :ok
  def cancel_session_cleanup(session_id) do
    GenServer.call(__MODULE__, {:cancel_timer, session_id})
  end

  @doc """
  Refreshes the TTL for a session by canceling the old timer and scheduling a new one.
  This is called when a session is actively used to extend its lifetime.
  """
  @spec refresh_session(binary()) :: reference()
  def refresh_session(session_id) do
    cancel_session_cleanup(session_id)
    schedule_session_cleanup(session_id)
  end
end
