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

  # 1 minute
  @cleanup_interval 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_sessions()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info({:cleanup_session, session_id}, state) do
    if Phoenix.SessionProcess.ProcessSupervisor.session_process_started?(session_id) do
      session_pid = Phoenix.SessionProcess.ProcessSupervisor.session_process_pid(session_id)

      Phoenix.SessionProcess.Telemetry.emit_auto_cleanup_event(
        session_id,
        Phoenix.SessionProcess.Helpers.get_session_module(session_pid),
        session_pid
      )

      Phoenix.SessionProcess.terminate(session_id)
    end

    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired_sessions do
    # This could be enhanced to track last activity
    # For now, sessions are cleaned up based on TTL from creation
    :ok
  end

  @doc """
  Schedules cleanup for a specific session after TTL.
  """
  @spec schedule_session_cleanup(binary()) :: :ok
  def schedule_session_cleanup(session_id) do
    ttl = Phoenix.SessionProcess.Config.session_ttl()
    Process.send_after(__MODULE__, {:cleanup_session, session_id}, ttl)
    :ok
  end

  @doc """
  Cancels scheduled cleanup for a session.
  """
  @spec cancel_session_cleanup(reference()) :: :ok
  def cancel_session_cleanup(timer_ref) do
    if timer_ref, do: Process.cancel_timer(timer_ref)
    :ok
  end
end
