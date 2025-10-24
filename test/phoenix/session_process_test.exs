defmodule Phoenix.SessionProcessTest do
  use ExUnit.Case
  # doctest Phoenix.SessionProcess  # Disabled to avoid test interference

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.SessionId

  setup do
    # Ensure supervisor is started
    unless Process.whereis(Phoenix.SessionProcess.Supervisor) do
      {:ok, _pid} = Phoenix.SessionProcess.Supervisor.start_link([])
    end

    # Clean up any existing session processes
    for {session_id, _pid} <- Phoenix.SessionProcess.list_session() do
      Phoenix.SessionProcess.terminate(session_id)
    end

    :ok
  end

  test "test start supervisor process" do
    assert Process.whereis(Phoenix.SessionProcess.Supervisor) != nil
    assert Process.whereis(Phoenix.SessionProcess.ProcessSupervisor) != nil
    assert Process.whereis(Phoenix.SessionProcess.Registry) != nil
  end

  test "test start session process" do
    session_id = SessionId.generate_unique_session_id()
    assert SessionProcess.started?(session_id) == false
    {:ok, pid} = SessionProcess.start(session_id, TestProcess, %{value: 0})
    assert is_pid(pid)
    assert SessionProcess.started?(session_id) == true
  end

  test "test terminate session process" do
    session_id = SessionId.generate_unique_session_id()
    {:ok, _pid} = SessionProcess.start(session_id, TestProcess, %{value: 0})
    assert SessionProcess.started?(session_id) == true
    SessionProcess.terminate(session_id)
    assert SessionProcess.started?(session_id) == false
  end

  test "test call on session process" do
    session_id = SessionId.generate_unique_session_id()
    {:ok, _pid} = SessionProcess.start(session_id, TestProcess, %{value: 123})
    assert SessionProcess.call(session_id, :get_value) == 123
  end

  test "test cast on session process" do
    session_id = SessionId.generate_unique_session_id()
    {:ok, _pid} = SessionProcess.start(session_id, TestProcess, %{value: 0})
    assert SessionProcess.call(session_id, :get_value) == 0
    SessionProcess.cast(session_id, :add_one)
    assert SessionProcess.call(session_id, :get_value) == 1
  end

  describe "list_session/0" do
    test "returns list type" do
      assert is_list(SessionProcess.list_session())
    end

    test "returns list of session_id and pid tuples" do
      session_id1 = SessionId.generate_unique_session_id()
      session_id2 = SessionId.generate_unique_session_id()

      {:ok, pid1} = SessionProcess.start(session_id1, TestProcess, %{value: 1})
      {:ok, pid2} = SessionProcess.start(session_id2, TestProcess, %{value: 2})

      sessions = SessionProcess.list_session()
      # Check that our created sessions are in the list
      assert {session_id1, pid1} in sessions
      assert {session_id2, pid2} in sessions

      # Cleanup
      SessionProcess.terminate(session_id1)
      SessionProcess.terminate(session_id2)
    end

    test "removes session when terminated" do
      session_id = SessionId.generate_unique_session_id()
      {:ok, pid} = SessionProcess.start(session_id, TestProcess, %{value: 0})

      # Check session exists in list
      sessions_before = SessionProcess.list_session()
      assert {session_id, pid} in sessions_before

      # Terminate and verify it's removed
      SessionProcess.terminate(session_id)
      sessions_after = SessionProcess.list_session()
      assert {session_id, pid} not in sessions_after
    end
  end

  describe "list_sessions_by_module/1" do
    test "returns list type" do
      assert is_list(SessionProcess.list_sessions_by_module(TestProcess))
    end

    test "returns session IDs for specific module" do
      session_id1 = SessionId.generate_unique_session_id()
      session_id2 = SessionId.generate_unique_session_id()

      {:ok, _pid1} = SessionProcess.start(session_id1, TestProcess, %{value: 1})
      {:ok, _pid2} = SessionProcess.start(session_id2, TestProcess, %{value: 2})

      sessions = SessionProcess.list_sessions_by_module(TestProcess)
      # Check that our created sessions are in the list
      assert session_id1 in sessions
      assert session_id2 in sessions

      # Cleanup
      SessionProcess.terminate(session_id1)
      SessionProcess.terminate(session_id2)
    end

    test "filters sessions by module correctly" do
      session_id1 = SessionId.generate_unique_session_id()
      session_id2 = SessionId.generate_unique_session_id()

      {:ok, _pid1} = SessionProcess.start(session_id1, TestProcess, %{value: 1})

      {:ok, _pid2} =
        SessionProcess.start(session_id2, TestProcessLink, %{value: 2})

      test_sessions = SessionProcess.list_sessions_by_module(TestProcess)
      link_sessions = SessionProcess.list_sessions_by_module(TestProcessLink)

      # Check that each session appears in the correct module list
      assert session_id1 in test_sessions
      assert session_id1 not in link_sessions
      assert session_id2 in link_sessions
      assert session_id2 not in test_sessions

      # Cleanup
      SessionProcess.terminate(session_id1)
      SessionProcess.terminate(session_id2)
    end
  end

  describe "session_info/0" do
    test "returns map with count and modules keys" do
      info = SessionProcess.session_info()
      assert is_map(info)
      assert Map.has_key?(info, :count)
      assert Map.has_key?(info, :modules)
      assert is_integer(info.count)
      assert is_list(info.modules)
    end

    test "includes modules of active sessions" do
      session_id1 = SessionId.generate_unique_session_id()
      session_id2 = SessionId.generate_unique_session_id()

      {:ok, _pid1} = SessionProcess.start(session_id1, TestProcess, %{value: 1})

      {:ok, _pid2} =
        SessionProcess.start(session_id2, TestProcessLink, %{value: 2})

      info = SessionProcess.session_info()
      # Check that both modules are in the list
      assert TestProcess in info.modules
      assert TestProcessLink in info.modules
      # Check that count is at least 2 (could be more from other tests)
      assert info.count >= 2

      # Cleanup
      SessionProcess.terminate(session_id1)
      SessionProcess.terminate(session_id2)
    end
  end

  describe "get_session_id/0 in :process macro" do
    test "returns correct session_id from within session process" do
      session_id = SessionId.generate_unique_session_id()
      {:ok, _pid} = SessionProcess.start(session_id, TestProcess, %{value: 0})

      # Call a function that uses get_session_id internally
      result = SessionProcess.call(session_id, :get_my_session_id)
      assert result == session_id
    end
  end

  describe "get_session_id/0 in :process_link macro" do
    test "returns correct session_id from within session process" do
      session_id = SessionId.generate_unique_session_id()
      {:ok, _pid} = SessionProcess.start(session_id, TestProcessLink, %{value: 0})

      result = SessionProcess.call(session_id, :get_my_session_id)
      assert result == session_id
    end
  end
end
