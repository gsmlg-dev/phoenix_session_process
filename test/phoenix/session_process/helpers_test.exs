defmodule Phoenix.SessionProcess.HelpersTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.Helpers

  setup do
    for {session_id, _pid} <- SessionProcess.list_session() do
      SessionProcess.terminate(session_id)
    end

    :ok
  end

  describe "broadcast_all/1" do
    test "returns :ok with no sessions" do
      assert :ok = Helpers.broadcast_all({:some, :message})
    end

    test "broadcasts to all sessions" do
      {:ok, _} = SessionProcess.start_session("bc_test_1")
      {:ok, _} = SessionProcess.start_session("bc_test_2")
      assert :ok = Helpers.broadcast_all({:put, :notified, true})
      Process.sleep(50)
    end
  end

  describe "session_health/0" do
    test "returns health stats with no sessions" do
      health = Helpers.session_health()
      assert health.healthy == 0
      assert health.crashed == 0
      assert health.total == 0
    end

    test "returns health stats with active sessions" do
      {:ok, _} = SessionProcess.start_session("health_1")
      {:ok, _} = SessionProcess.start_session("health_2")
      health = Helpers.session_health()
      assert health.healthy >= 2
      assert health.crashed == 0
      assert health.total >= 2
    end
  end

  describe "find_sessions_by_pattern/1" do
    test "finds matching sessions" do
      {:ok, _} = SessionProcess.start_session("pat_user_1")
      {:ok, _} = SessionProcess.start_session("pat_user_2")
      {:ok, _} = SessionProcess.start_session("pat_admin_1")
      results = Helpers.find_sessions_by_pattern(~r/pat_user_.*/)
      assert length(results) == 2
      assert "pat_user_1" in results
      assert "pat_user_2" in results
    end

    test "returns empty for no matches" do
      {:ok, _} = SessionProcess.start_session("nomatch_x")
      assert [] = Helpers.find_sessions_by_pattern(~r/xyz_.*/)
    end
  end

  describe "start_sessions/1" do
    test "starts multiple sessions in parallel" do
      results = Helpers.start_sessions(["multi_1", "multi_2", "multi_3"])
      assert length(results) == 3

      for {_id, result} <- results do
        assert {:ok, pid} = result
        assert is_pid(pid)
      end
    end
  end

  describe "terminate_sessions/1" do
    test "terminates multiple sessions in parallel" do
      {:ok, _} = SessionProcess.start_session("term_1")
      {:ok, _} = SessionProcess.start_session("term_2")
      results = Helpers.terminate_sessions(["term_1", "term_2"])
      assert length(results) == 2

      for {_id, result} <- results do
        assert result == :ok
      end
    end
  end

  describe "safe_call/4" do
    test "returns error for non-existent session" do
      assert {:error, _} = Helpers.safe_call("nonexistent_safe", :get_value, 1)
    end
  end

  describe "create_session_with_retry/4" do
    test "creates a session successfully" do
      assert {:ok, pid} = Helpers.create_session_with_retry("retry_1")
      assert is_pid(pid)
      assert SessionProcess.started?("retry_1")
    end
  end

  describe "get_session_module/1" do
    test "returns module for active session" do
      {:ok, pid} = SessionProcess.start_session("mod_1")
      module = Helpers.get_session_module(pid)
      assert is_atom(module)
    end
  end
end
