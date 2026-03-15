defmodule Phoenix.SessionProcess.DefaultSessionProcessTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess.DefaultSessionProcess

  setup do
    {:ok, pid} = start_supervised({DefaultSessionProcess, name: :test_session})
    %{pid: pid}
  end

  test "starts with empty state" do
    full_state = :sys.get_state(:test_session)
    assert %{} = full_state.app_state
  end

  test "handles :ping call" do
    assert :pong = GenServer.call(:test_session, :ping)
  end

  test "handles :get_state call" do
    {:ok, app_state} = GenServer.call(:test_session, :get_state)
    assert %{} = app_state
  end

  test "handles put cast" do
    GenServer.cast(:test_session, {:put, :key, "value"})
    # Allow cast to process
    Process.sleep(10)
    {:ok, app_state} = GenServer.call(:test_session, :get_state)
    assert %{key: "value"} = app_state
  end

  test "handles delete cast" do
    # First add some data
    GenServer.cast(:test_session, {:put, :key1, "value1"})
    GenServer.cast(:test_session, {:put, :key2, "value2"})
    Process.sleep(10)

    # Delete one key
    GenServer.cast(:test_session, {:delete, :key1})
    Process.sleep(10)

    {:ok, app_state} = GenServer.call(:test_session, :get_state)
    assert %{key2: "value2"} = app_state
  end

  test "handles multiple operations" do
    # Add data
    GenServer.cast(:test_session, {:put, :user_id, 123})
    GenServer.cast(:test_session, {:put, :username, "test_user"})
    Process.sleep(10)

    # Verify state
    {:ok, app_state} = GenServer.call(:test_session, :get_state)
    assert %{user_id: 123, username: "test_user"} = app_state

    # Delete one key
    GenServer.cast(:test_session, {:delete, :username})
    Process.sleep(10)

    {:ok, app_state2} = GenServer.call(:test_session, :get_state)
    assert %{user_id: 123} = app_state2
    assert :pong = GenServer.call(:test_session, :ping)
  end
end
