defmodule Phoenix.SessionProcess.MacroConsistencyTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess

  defmodule TestProcessWithArg do
    use Phoenix.SessionProcess, :process

    def init(arg) do
      {:ok, %{initialized_with: arg}}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  defmodule TestProcessLinkWithArg do
    use Phoenix.SessionProcess, :process

    def init(arg) do
      {:ok, %{initialized_with: arg}}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  describe ":process macro with :arg parameter" do
    test "accepts initialization argument" do
      session_id = "test_process_with_arg_#{:rand.uniform(10000)}"
      init_arg = %{user_id: 123, data: "test"}

      {:ok, _pid} = SessionProcess.start(session_id, TestProcessWithArg, init_arg)

      state = SessionProcess.call(session_id, :get_state)
      assert state.initialized_with == init_arg

      SessionProcess.terminate(session_id)
    end
  end

  describe ":process macro with :arg parameter (renamed from :process_link)" do
    test "accepts initialization argument with same parameter name" do
      session_id = "test_process_link_with_arg_#{:rand.uniform(10000)}"
      init_arg = %{user_id: 456, data: "test"}

      {:ok, _pid} = SessionProcess.start(session_id, TestProcessLinkWithArg, init_arg)

      state = SessionProcess.call(session_id, :get_state)
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
      {:ok, _} = SessionProcess.start(session_id_1, TestProcessWithArg, init_arg)
      {:ok, _} = SessionProcess.start(session_id_2, TestProcessLinkWithArg, init_arg)

      state1 = SessionProcess.call(session_id_1, :get_state)
      state2 = SessionProcess.call(session_id_2, :get_state)

      assert state1.initialized_with == init_arg
      assert state2.initialized_with == init_arg

      SessionProcess.terminate(session_id_1)
      SessionProcess.terminate(session_id_2)
    end
  end
end
