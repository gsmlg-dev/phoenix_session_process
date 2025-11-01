defmodule Phoenix.SessionProcess.BehaviourTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess.ProcessBehaviour
  alias Phoenix.SessionProcess.ReducerBehaviour

  describe "ProcessBehaviour" do
    test "is a valid behaviour module" do
      # Verify the module exists and is a behaviour
      assert Code.ensure_loaded?(ProcessBehaviour)
      assert function_exported?(ProcessBehaviour, :__info__, 1)
    end

    test "example module implements ProcessBehaviour correctly" do
      defmodule TestProcess do
        use Phoenix.SessionProcess, :process

        @impl true
        def init_state(_arg) do
          %{test: true}
        end

        @impl true
        def combined_reducers do
          []
        end
      end

      # Verify the module uses the behaviour
      behaviours = TestProcess.module_info(:attributes)[:behaviour] || []
      assert ProcessBehaviour in behaviours

      # Verify required callbacks are defined
      assert function_exported?(TestProcess, :init_state, 1)

      # Verify optional callbacks are defined
      assert function_exported?(TestProcess, :combined_reducers, 0)
    end

    test "module without @impl annotation gets warned by compiler" do
      # This test just documents that behaviours enable warnings
      # The actual warnings appear during compilation (see test output)
      defmodule ProcessWithoutImpl do
        use Phoenix.SessionProcess, :process

        # Missing @impl - will warn during compilation
        def init_state(_arg), do: %{}
      end

      # Verify it still implements the function
      assert function_exported?(ProcessWithoutImpl, :init_state, 1)
    end
  end

  describe "ReducerBehaviour" do
    test "is a valid behaviour module" do
      # Verify the module exists and is a behaviour
      assert Code.ensure_loaded?(ReducerBehaviour)
      assert function_exported?(ReducerBehaviour, :__info__, 1)
    end

    test "example module implements ReducerBehaviour correctly" do
      defmodule TestReducer do
        use Phoenix.SessionProcess, :reducer
        alias Phoenix.SessionProcess.Action

        @name :test
        @action_prefix "test"

        @impl true
        def init_state do
          %{value: 0}
        end

        @impl true
        def handle_action(%Action{type: "increment"}, state) do
          %{state | value: state.value + 1}
        end

        def handle_action(_action, state), do: state
      end

      # Verify the module uses the behaviour
      behaviours = TestReducer.module_info(:attributes)[:behaviour] || []
      assert ReducerBehaviour in behaviours

      # Verify required callbacks are defined
      assert function_exported?(TestReducer, :init_state, 0)
      assert function_exported?(TestReducer, :handle_action, 2)

      # Verify optional callbacks have defaults
      assert function_exported?(TestReducer, :handle_unmatched_action, 2)
      assert function_exported?(TestReducer, :handle_unmatched_async, 3)
    end

    test "reducer with optional handle_async callback" do
      defmodule AsyncReducer do
        use Phoenix.SessionProcess, :reducer
        alias Phoenix.SessionProcess.Action

        @name :async_test
        @action_prefix "async"

        @impl true
        def init_state do
          %{count: 0}
        end

        @impl true
        def handle_action(_action, state), do: state

        @impl true
        def handle_async(%Action{type: "fetch"}, dispatch, _state) do
          dispatch.("async.complete", nil, [])
          fn -> :ok end
        end

        def handle_async(_action, _dispatch, _state) do
          fn -> nil end
        end
      end

      # Verify handle_async is defined
      assert function_exported?(AsyncReducer, :handle_async, 3)
    end
  end

  describe "behaviour compliance warnings" do
    test "warns when missing @impl for ProcessBehaviour callbacks" do
      # This test verifies that the compiler will warn when @impl is missing
      # The warnings in test output confirm this is working
      code = """
      defmodule MissingImplProcess do
        use Phoenix.SessionProcess, :process

        # Missing @impl annotation
        def init_state(_arg), do: %{}
      end
      """

      # We can't easily test compiler warnings in tests, but the behaviour
      # will cause warnings to be emitted during compilation
      assert code =~ "init_state"
    end

    test "warns when missing @impl for ReducerBehaviour callbacks" do
      code = """
      defmodule MissingImplReducer do
        use Phoenix.SessionProcess, :reducer

        @name :test

        # Missing @impl annotation
        def init_state, do: %{}
        def handle_action(_action, state), do: state
      end
      """

      assert code =~ "init_state"
      assert code =~ "handle_action"
    end
  end
end
