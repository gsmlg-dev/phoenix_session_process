defmodule Phoenix.SessionProcess.SessionStatsTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess

  setup do
    for {session_id, _pid} <- SessionProcess.list_session() do
      SessionProcess.terminate(session_id)
    end

    :ok
  end

  describe "session_stats/0" do
    test "returns stats map with correct keys" do
      stats = SessionProcess.session_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :total_sessions)
      assert Map.has_key?(stats, :memory_usage)
      assert Map.has_key?(stats, :avg_memory_per_session)
    end

    test "returns zero values with no sessions" do
      stats = SessionProcess.session_stats()
      assert stats.total_sessions == 0
      assert stats.memory_usage == 0
      assert stats.avg_memory_per_session == 0
    end

    test "returns correct count with active sessions" do
      {:ok, _} = SessionProcess.start_session("stats_1")
      {:ok, _} = SessionProcess.start_session("stats_2")
      stats = SessionProcess.session_stats()
      assert stats.total_sessions >= 2
    end

    test "reports positive memory for active sessions" do
      {:ok, _} = SessionProcess.start_session("stats_mem_1")
      {:ok, _} = SessionProcess.start_session("stats_mem_2")
      stats = SessionProcess.session_stats()
      assert stats.memory_usage > 0
      assert stats.avg_memory_per_session > 0
    end

    test "average memory equals total divided by count" do
      {:ok, _} = SessionProcess.start_session("stats_avg_1")
      {:ok, _} = SessionProcess.start_session("stats_avg_2")
      stats = SessionProcess.session_stats()
      expected_avg = div(stats.memory_usage, stats.total_sessions)
      assert stats.avg_memory_per_session == expected_avg
    end
  end
end
