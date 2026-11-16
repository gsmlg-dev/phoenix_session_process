defmodule Phoenix.SessionProcess.MacroCompilationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Phoenix.SessionProcess

  defmodule CounterReducer do
    use Phoenix.SessionProcess, :reducer

    alias Phoenix.SessionProcess.Action

    @name :counter
    @action_prefix "counter"

    @impl true
    def init_state, do: %{count: 0}

    @impl true
    def handle_action(%Action{type: "increment"}, state), do: %{state | count: state.count + 1}
    def handle_action(_action, state), do: state
  end

  for {name, reducers, slices} <- [
        {:DefaultSession, nil, []},
        {:EmptyListSession, "[]", []},
        {:ModuleListSession, "[#{inspect(CounterReducer)}]", [:counter]},
        {:TupleListSession,
         "[{:renamed, #{inspect(CounterReducer)}}, {:custom, #{inspect(CounterReducer)}, \"other\"}, {:global, #{inspect(CounterReducer)}, nil}]",
         [:renamed, :custom, :global]},
        {:EmptyMapSession, "%{}", []},
        {:LegacyMapSession, "%{legacy: #{inspect(CounterReducer)}}", [:legacy]}
      ] do
    callback =
      if reducers do
        "@impl true\ndef combined_reducers, do: #{reducers}"
      else
        ""
      end

    test "#{name} compiles without warnings and initializes reducer slices" do
      module = Module.concat(__MODULE__, unquote(name))

      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
      end)

      diagnostics =
        capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule #{inspect(module)} do
            use Phoenix.SessionProcess, :process

            @impl true
            def init_state(_), do: %{initialized: true}

            #{unquote(callback)}
          end
          """)
        end)

      assert diagnostics == ""

      session_id = "macro_compile_#{unquote(name)}"
      assert {:ok, _pid} = SessionProcess.start_session(session_id, module: module)
      on_exit(fn -> SessionProcess.terminate(session_id) end)

      expected = Map.new(unquote(slices), &{&1, %{count: 0}})
      assert SessionProcess.get_state(session_id) == Map.put(expected, :initialized, true)

      assert :ok = SessionProcess.dispatch(session_id, "increment")
      updated = Map.new(unquote(slices), &{&1, %{count: 1}})
      assert SessionProcess.get_state(session_id) == Map.put(updated, :initialized, true)
    end
  end
end
