defmodule Phoenix.SessionProcess.MacroConsistencyTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess

  defmodule TestProcessWithArg do
    use Phoenix.SessionProcess, :process

    @impl true
    def init_state(arg) do
      %{initialized_with: arg}
    end
  end

  defmodule TestProcessLinkWithArg do
    use Phoenix.SessionProcess, :process

    @impl true
    def init_state(arg) do
      %{initialized_with: arg}
    end
  end

  describe ":process macro with :arg parameter" do
    test "accepts initialization argument" do
      session_id = "test_process_with_arg_#{:rand.uniform(10000)}"
      init_arg = %{user_id: 123, data: "test"}

      {:ok, _pid} =
        SessionProcess.start_session(session_id, module: TestProcessWithArg, args: init_arg)

      state = SessionProcess.get_state(session_id)
      assert state.initialized_with == init_arg

      SessionProcess.terminate(session_id)
    end

    test "accepts initialization argument with different module" do
      session_id = "test_process_with_arg_#{:rand.uniform(10000)}"
      init_arg = %{user_id: 456, data: "test"}

      {:ok, _pid} =
        SessionProcess.start_session(session_id, module: TestProcessLinkWithArg, args: init_arg)

      state = SessionProcess.get_state(session_id)
      assert state.initialized_with == init_arg

      SessionProcess.terminate(session_id)
    end
  end

  describe ":process macro uses consistent parameter names" do
    test "both test modules work with :arg" do
      session_id_1 = "consistency_test_1_#{:rand.uniform(10000)}"
      session_id_2 = "consistency_test_2_#{:rand.uniform(10000)}"

      init_arg = %{value: 42}

      # Both should accept the same argument format
      {:ok, _} =
        SessionProcess.start_session(session_id_1, module: TestProcessWithArg, args: init_arg)

      {:ok, _} =
        SessionProcess.start_session(session_id_2, module: TestProcessLinkWithArg, args: init_arg)

      state1 = SessionProcess.get_state(session_id_1)
      state2 = SessionProcess.get_state(session_id_2)

      assert state1.initialized_with == init_arg
      assert state2.initialized_with == init_arg

      SessionProcess.terminate(session_id_1)
      SessionProcess.terminate(session_id_2)
    end
  end
end
