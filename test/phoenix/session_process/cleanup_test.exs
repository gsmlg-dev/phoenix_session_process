defmodule Phoenix.SessionProcess.CleanupTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.{ActivityTracker, Cleanup, Config, SessionId}

  defmodule TemporarySession do
    @moduledoc false
    use GenServer, restart: :temporary

    def start_link(opts), do: GenServer.start_link(__MODULE__, nil, name: opts[:name])

    @impl true
    def init(_arg), do: {:ok, nil}
  end

  test "explicit termination removes activity and cancels the cleanup timer" do
    session_id = SessionId.generate_unique_session_id()
    assert {:ok, _pid} = SessionProcess.start_session(session_id)
    timer_ref = :sys.get_state(Cleanup).timers[session_id]
    assert {:ok, _timestamp} = ActivityTracker.get_last_activity(session_id)

    assert :ok = SessionProcess.terminate(session_id)

    refute SessionProcess.started?(session_id)
    assert {:error, :not_found} = ActivityTracker.get_last_activity(session_id)
    refute Map.has_key?(:sys.get_state(Cleanup).timers, session_id)
    assert Process.read_timer(timer_ref) == false
  end

  test "scheduled cleanup removes stale activity after a session crashes" do
    session_id = SessionId.generate_unique_session_id()
    assert {:ok, pid} = SessionProcess.start_session(session_id, module: TemporarySession)
    timer_ref = :sys.get_state(Cleanup).timers[session_id]
    monitor_ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor_ref, :process, ^pid, :killed}
    refute SessionProcess.started?(session_id)
    assert {:ok, _timestamp} = ActivityTracker.get_last_activity(session_id)

    send(Cleanup, {:cleanup_session, session_id})
    state = :sys.get_state(Cleanup)

    assert {:error, :not_found} = ActivityTracker.get_last_activity(session_id)
    refute Map.has_key?(state.timers, session_id)
    assert Process.read_timer(timer_ref) == false
  end

  test "scheduled expiration terminates the session without restarting Cleanup" do
    session_id = SessionId.generate_unique_session_id()
    assert {:ok, _pid} = SessionProcess.start_session(session_id)
    cleanup_pid = Process.whereis(Cleanup)
    timer_ref = :sys.get_state(cleanup_pid).timers[session_id]
    expired_at = System.system_time(:millisecond) - Config.session_ttl() - 1
    :ets.insert(:session_activity, {session_id, expired_at})

    send(cleanup_pid, {:cleanup_session, session_id})
    state = :sys.get_state(cleanup_pid)

    assert Process.whereis(Cleanup) == cleanup_pid
    refute SessionProcess.started?(session_id)
    assert {:error, :not_found} = ActivityTracker.get_last_activity(session_id)
    refute Map.has_key?(state.timers, session_id)
    assert Process.read_timer(timer_ref) == false
  end

  test "periodic expiration terminates the session and cancels its timer" do
    session_id = SessionId.generate_unique_session_id()
    assert {:ok, _pid} = SessionProcess.start_session(session_id)
    cleanup_pid = Process.whereis(Cleanup)
    timer_ref = :sys.get_state(cleanup_pid).timers[session_id]
    expired_at = System.system_time(:millisecond) - Config.session_ttl() - 1
    :ets.insert(:session_activity, {session_id, expired_at})

    send(cleanup_pid, :cleanup)
    state = :sys.get_state(cleanup_pid)

    assert Process.whereis(Cleanup) == cleanup_pid
    refute SessionProcess.started?(session_id)
    assert {:error, :not_found} = ActivityTracker.get_last_activity(session_id)
    refute Map.has_key?(state.timers, session_id)
    assert Process.read_timer(timer_ref) == false
  end

  test "cancellation removes activity even when no timer remains" do
    session_id = SessionId.generate_unique_session_id()
    assert :ok = ActivityTracker.touch(session_id)
    refute Map.has_key?(:sys.get_state(Cleanup).timers, session_id)

    assert :ok = Cleanup.cancel_session_cleanup(session_id)
    assert {:error, :not_found} = ActivityTracker.get_last_activity(session_id)
  end

  test "scheduled cleanup preserves a session that is still active" do
    session_id = SessionId.generate_unique_session_id()
    assert {:ok, pid} = SessionProcess.start_session(session_id)

    send(Cleanup, {:cleanup_session, session_id})
    :sys.get_state(Cleanup)

    assert Process.alive?(pid)
    assert SessionProcess.started?(session_id)
    assert {:ok, _timestamp} = ActivityTracker.get_last_activity(session_id)
    assert :ok = SessionProcess.terminate(session_id)
    assert {:error, :not_found} = ActivityTracker.get_last_activity(session_id)
  end

  test "schedule_session_cleanup/1 returns timer reference" do
    session_id = "test_session"
    timer_ref = Cleanup.schedule_session_cleanup(session_id)
    assert is_reference(timer_ref)
  end

  test "cancel_session_cleanup/1 cancels scheduled cleanup" do
    session_id = "test_session_cancel"

    # Schedule cleanup
    timer_ref = Cleanup.schedule_session_cleanup(session_id)

    # Verify timer exists
    assert is_reference(timer_ref)

    # Cancel it
    assert :ok = Cleanup.cancel_session_cleanup(session_id)
  end

  test "refresh_session/1 reschedules cleanup" do
    session_id = "test_session_refresh"

    # Schedule initial cleanup
    timer_ref1 = Cleanup.schedule_session_cleanup(session_id)
    assert is_reference(timer_ref1)

    # Wait a bit
    Process.sleep(10)

    # Refresh should cancel old and create new
    timer_ref2 = Cleanup.refresh_session(session_id)
    assert is_reference(timer_ref2)
    # New reference should be different
    assert timer_ref1 != timer_ref2
  end
end
