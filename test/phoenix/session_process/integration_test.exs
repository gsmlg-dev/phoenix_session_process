defmodule Phoenix.SessionProcess.IntegrationTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess

  test "session validation and limits" do
    # Test invalid session ID
    assert {:error, {:invalid_session_id, "invalid@session"}} =
             SessionProcess.start_session("invalid@session")

    # Test empty session ID
    assert {:error, {:invalid_session_id, ""}} = SessionProcess.start_session("")
  end

  test "error handling for non-existent sessions" do
    non_existent_session = "does_not_exist"

    assert {:error, {:session_not_found, "does_not_exist"}} =
             SessionProcess.call(non_existent_session, :get_state)

    assert {:error, {:session_not_found, "does_not_exist"}} =
             SessionProcess.cast(non_existent_session, {:put, :key, "value"})

    assert {:error, {:session_not_found, "does_not_exist"}} =
             SessionProcess.terminate(non_existent_session)
  end

  test "session process can use custom modules" do
    defmodule TestCustomSession do
      use Phoenix.SessionProcess, :process

      def init(_init_arg) do
        {:ok, %{custom: true}}
      end

      def handle_call(:custom_call, _from, state) do
        {:reply, {:custom_response, state}, state}
      end

      def handle_call(:get_state, _from, state) do
        {:reply, state, state}
      end
    end

    session_id = "custom_module_test"

    # Start with custom module
    assert {:ok, _pid} =
             SessionProcess.start_session(session_id, module: TestCustomSession, args: %{test: "data"})

    # Verify custom initialization worked
    assert %{custom: true} = SessionProcess.call(session_id, :get_state)
    assert {:custom_response, %{custom: true}} = SessionProcess.call(session_id, :custom_call)

    # Clean up
    :ok = SessionProcess.terminate(session_id)
  end
end
