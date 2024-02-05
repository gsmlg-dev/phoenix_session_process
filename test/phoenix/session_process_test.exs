defmodule Phoenix.SessionProcessTest do
  use ExUnit.Case
  doctest Phoenix.SessionProcess

  alias Phoenix.SessionProcess

  test "test start supervisor process" do
    assert Process.whereis(SessionProcess.Supervisor) != nil
    assert Process.whereis(SessionProcess.ProcessSupervisor) != nil
    assert Process.whereis(SessionProcess.Registry) != nil
  end

  test "test start session process" do
    session_id = SessionProcess.SessionId.generate_unique_session_id()
    assert SessionProcess.started?(session_id) == false
    SessionProcess.start(session_id)
    assert SessionProcess.started?(session_id) == true
  end

  test "test terminate session process" do
    session_id = SessionProcess.SessionId.generate_unique_session_id()
    SessionProcess.start(session_id)
    assert SessionProcess.started?(session_id) == true
    SessionProcess.terminate(session_id)
    assert SessionProcess.started?(session_id) == false
  end

  test "test call on session process" do
    session_id = SessionProcess.SessionId.generate_unique_session_id()
    SessionProcess.start(session_id)
    assert SessionProcess.call(session_id, :get_value) == %{}
  end

  test "test cast on session process" do
    session_id = SessionProcess.SessionId.generate_unique_session_id()
    SessionProcess.start(session_id, TestProcess, 0)
    assert SessionProcess.call(session_id, :get_value) == 0
    SessionProcess.cast(session_id, :add_one)
    assert SessionProcess.call(session_id, :get_value) == 1
  end
end
