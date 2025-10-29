defmodule Phoenix.SessionProcess.CleanupTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess.Cleanup

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
