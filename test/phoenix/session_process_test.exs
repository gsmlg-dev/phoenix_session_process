defmodule Phoenix.SessionProcessTest do
  use ExUnit.Case
  doctest Phoenix.SessionProcess

  alias Phoenix.SessionProcess

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
    session_id = Phoenix.SessionProcess.SessionId.generate_unique_session_id()
    assert SessionProcess.started?(session_id) == false
    {:ok, pid} = SessionProcess.start(session_id, TestProcess, %{value: 0})
    assert is_pid(pid)
    assert SessionProcess.started?(session_id) == true
  end

  test "test terminate session process" do
    session_id = Phoenix.SessionProcess.SessionId.generate_unique_session_id()
    {:ok, _pid} = SessionProcess.start(session_id, TestProcess, %{value: 0})
    assert SessionProcess.started?(session_id) == true
    SessionProcess.terminate(session_id)
    assert SessionProcess.started?(session_id) == false
  end

  test "test call on session process" do
    session_id = Phoenix.SessionProcess.SessionId.generate_unique_session_id()
    {:ok, _pid} = SessionProcess.start(session_id, TestProcess, %{value: 123})
    assert SessionProcess.call(session_id, :get_value) == 123
  end

  test "test cast on session process" do
    session_id = Phoenix.SessionProcess.SessionId.generate_unique_session_id()
    {:ok, _pid} = SessionProcess.start(session_id, TestProcess, %{value: 0})
    assert SessionProcess.call(session_id, :get_value) == 0
    SessionProcess.cast(session_id, :add_one)
    assert SessionProcess.call(session_id, :get_value) == 1
  end
end
