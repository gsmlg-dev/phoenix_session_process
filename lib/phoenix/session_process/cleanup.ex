defmodule Phoenix.SessionProcess.Cleanup do
  @moduledoc """
  Automatic session cleanup with TTL support.
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
      Logger.debug("Auto-cleanup expired session: #{session_id}")
      Phoenix.SessionProcess.terminate(session_id)
    end

    {:noreply, state}
  end

  defp schedule_cleanup() do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired_sessions() do
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
