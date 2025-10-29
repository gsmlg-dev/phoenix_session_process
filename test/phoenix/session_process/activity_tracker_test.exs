defmodule Phoenix.SessionProcess.ActivityTrackerTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess.ActivityTracker

  setup do
    ActivityTracker.init()
    ActivityTracker.clear()
    :ok
  end

  describe "touch/1" do
    test "records activity for a session" do
      assert :ok = ActivityTracker.touch("session_123")

      assert {:ok, timestamp} = ActivityTracker.get_last_activity("session_123")
      assert is_integer(timestamp)
      assert timestamp > 0
    end

    test "updates activity timestamp on subsequent touches" do
      ActivityTracker.touch("session_123")
      {:ok, first_timestamp} = ActivityTracker.get_last_activity("session_123")

      # Wait a bit
      Process.sleep(10)

      ActivityTracker.touch("session_123")
      {:ok, second_timestamp} = ActivityTracker.get_last_activity("session_123")

      assert second_timestamp > first_timestamp
    end
  end

  describe "get_last_activity/1" do
    test "returns error for session with no activity" do
      assert {:error, :not_found} = ActivityTracker.get_last_activity("nonexistent")
    end

    test "returns timestamp for session with activity" do
      ActivityTracker.touch("session_123")
      assert {:ok, _timestamp} = ActivityTracker.get_last_activity("session_123")
    end
  end

  describe "expired?/2" do
    test "returns false for recently active sessions" do
      ActivityTracker.touch("session_123")
      refute ActivityTracker.expired?("session_123", ttl: 5000)
    end

    test "returns true for sessions past TTL" do
      # Simulate old activity by manually inserting old timestamp
      old_timestamp = System.system_time(:millisecond) - 10_000
      :ets.insert(:session_activity, {"session_old", old_timestamp})

      assert ActivityTracker.expired?("session_old", ttl: 5000)
    end

    test "returns false for sessions with no activity (assumed new)" do
      refute ActivityTracker.expired?("never_touched", ttl: 5000)
    end
  end

  describe "remove/1" do
    test "removes activity tracking for a session" do
      ActivityTracker.touch("session_123")
      assert {:ok, _} = ActivityTracker.get_last_activity("session_123")

      ActivityTracker.remove("session_123")
      assert {:error, :not_found} = ActivityTracker.get_last_activity("session_123")
    end
  end

  describe "get_expired_sessions/1" do
    test "returns list of expired sessions" do
      now = System.system_time(:millisecond)
      old_time = now - 10_000

      # Insert some sessions with different timestamps
      :ets.insert(:session_activity, {"session_old_1", old_time})
      :ets.insert(:session_activity, {"session_old_2", old_time - 1000})
      :ets.insert(:session_activity, {"session_recent", now})

      expired = ActivityTracker.get_expired_sessions(ttl: 5000)

      assert "session_old_1" in expired
      assert "session_old_2" in expired
      refute "session_recent" in expired
    end
  end

  describe "count/0" do
    test "returns number of tracked sessions" do
      assert ActivityTracker.count() == 0

      ActivityTracker.touch("session_1")
      assert ActivityTracker.count() == 1

      ActivityTracker.touch("session_2")
      ActivityTracker.touch("session_3")
      assert ActivityTracker.count() == 3
    end
  end

  describe "clear/0" do
    test "removes all activity tracking" do
      ActivityTracker.touch("session_1")
      ActivityTracker.touch("session_2")
      assert ActivityTracker.count() == 2

      ActivityTracker.clear()
      assert ActivityTracker.count() == 0
    end
  end
end
