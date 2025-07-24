defmodule Phoenix.SessionProcess.DefaultSessionProcessTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess.DefaultSessionProcess

  setup do
    {:ok, pid} = start_supervised({DefaultSessionProcess, name: :test_session})
    %{pid: pid}
  end

  test "starts with empty state" do
    assert %{} = :sys.get_state(:test_session)
  end

  test "handles :ping call" do
    assert :pong = GenServer.call(:test_session, :ping)
  end

  test "handles :get_state call" do
    assert %{} = GenServer.call(:test_session, :get_state)
  end

  test "handles put cast" do
    GenServer.cast(:test_session, {:put, :key, "value"})
    # Allow cast to process
    Process.sleep(10)
    assert %{key: "value"} = GenServer.call(:test_session, :get_state)
  end

  test "handles delete cast" do
    # First add some data
    GenServer.cast(:test_session, {:put, :key1, "value1"})
    GenServer.cast(:test_session, {:put, :key2, "value2"})
    Process.sleep(10)

    # Delete one key
    GenServer.cast(:test_session, {:delete, :key1})
    Process.sleep(10)

    assert %{key2: "value2"} = GenServer.call(:test_session, :get_state)
  end

  test "handles multiple operations" do
    # Add data
    GenServer.cast(:test_session, {:put, :user_id, 123})
    GenServer.cast(:test_session, {:put, :username, "test_user"})
    Process.sleep(10)

    # Verify state
    assert %{user_id: 123, username: "test_user"} = GenServer.call(:test_session, :get_state)

    # Delete one key
    GenServer.cast(:test_session, {:delete, :username})
    Process.sleep(10)

    assert %{user_id: 123} = GenServer.call(:test_session, :get_state)
    assert :pong = GenServer.call(:test_session, :ping)
  end
end
