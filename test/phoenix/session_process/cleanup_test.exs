defmodule Phoenix.SessionProcess.CleanupTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess.Cleanup

  test "schedule_session_cleanup/1 returns :ok" do
    session_id = "test_session_123"
    assert :ok = Cleanup.schedule_session_cleanup(session_id)
  end

  test "cancel_session_cleanup/1 cancels scheduled cleanup" do
    timer_ref = Process.send_after(self(), :test, 1000)

    # Verify timer exists
    assert is_reference(timer_ref)

    # Cancel the timer
    assert :ok = Cleanup.cancel_session_cleanup(timer_ref)

    # Verify timer was cancelled
    refute Process.read_timer(timer_ref)
  end

  test "cleanup module functions work" do
    assert function_exported?(Cleanup, :schedule_session_cleanup, 1)
    assert function_exported?(Cleanup, :cancel_session_cleanup, 1)
    assert function_exported?(Cleanup, :start_link, 1)
  end
end
