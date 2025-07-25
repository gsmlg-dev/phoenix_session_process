defmodule Phoenix.SessionProcess.StateTest do
  use ExUnit.Case, async: true
  alias Phoenix.SessionProcess.State

  describe "start_link/1" do
    test "starts with default state" do
      {:ok, pid} = State.start_link()
      assert State.get_state(pid) == %{}
    end

    test "starts with custom initial state" do
      initial_state = %{count: 0, user: nil}
      {:ok, pid} = State.start_link(initial_state)
      assert State.get_state(pid) == initial_state
    end
  end

  describe "get/2" do
    test "gets value by key" do
      {:ok, pid} = State.start_link(%{name: "Alice", age: 30})

      assert State.get(pid, :name) == "Alice"
      assert State.get(pid, :age) == 30
      assert State.get(pid, :nonexistent) == nil
    end
  end

  describe "put/3" do
    test "puts value by key" do
      {:ok, pid} = State.start_link(%{count: 0})

      :ok = State.put(pid, :count, 5)
      assert State.get(pid, :count) == 5

      :ok = State.put(pid, :user, "Bob")
      assert State.get(pid, :user) == "Bob"
    end
  end

  describe "get_state/1 and update_state/2" do
    test "gets entire state" do
      state = %{user: "Alice", settings: %{theme: :dark}}
      {:ok, pid} = State.start_link(state)

      assert State.get_state(pid) == state
    end

    test "updates entire state" do
      {:ok, pid} = State.start_link(%{count: 0})

      State.update_state(pid, fn state -> %{state | count: state.count + 10} end)
      assert State.get_state(pid) == %{count: 10}

      State.update_state(pid, fn _ -> %{reset: true} end)
      assert State.get_state(pid) == %{reset: true}
    end
  end

  describe "dispatch/3 with function reducer" do
    test "dispatches actions with function reducer" do
      {:ok, pid} = State.start_link(%{count: 0})

      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end

      State.dispatch(pid, {:increment, 5}, reducer)
      assert State.get_state(pid) == %{count: 5}

      State.dispatch(pid, {:increment, 3}, reducer)
      assert State.get_state(pid) == %{count: 8}
    end

    test "handles complex actions" do
      {:ok, pid} = State.start_link(%{count: 0, user: nil, log: []})

      reducer = fn state, action ->
        case action do
          {:increment, val} ->
            %{state | count: state.count + val, log: ["+#{val}" | state.log]}

          {:set_user, user} ->
            %{state | user: user, log: ["user:#{user}" | state.log]}

          _ ->
            state
        end
      end

      State.dispatch(pid, {:increment, 5}, reducer)
      State.dispatch(pid, {:set_user, "Alice"}, reducer)
      State.dispatch(pid, {:increment, 2}, reducer)

      expected = %{count: 7, user: "Alice", log: ["+2", "user:Alice", "+5"]}
      assert State.get_state(pid) == expected
    end

    test "handles nested state updates" do
      {:ok, pid} = State.start_link(%{user: %{profile: %{name: ""}}, settings: %{}})

      reducer = fn state, {:update_name, name} ->
        %{state | user: %{state.user | profile: %{state.user.profile | name: name}}}
      end

      State.dispatch(pid, {:update_name, "Alice"}, reducer)

      expected = %{user: %{profile: %{name: "Alice"}}, settings: %{}}
      assert State.get_state(pid) == expected
    end
  end

  describe "dispatch/3 with module reducer" do
    defmodule TestStateReducer do
      def reduce(state, {:add, val}), do: %{state | total: state.total + val}
      def reduce(state, {:multiply, val}), do: %{state | total: state.total * val}
      def reduce(state, _), do: state
    end

    test "dispatches actions with module reducer" do
      {:ok, pid} = State.start_link(%{total: 0})

      State.dispatch(pid, {:add, 5}, TestStateReducer)
      assert State.get_state(pid) == %{total: 5}

      State.dispatch(pid, {:multiply, 2}, TestStateReducer)
      assert State.get_state(pid) == %{total: 10}

      State.dispatch(pid, {:unknown_action, 100}, TestStateReducer)
      assert State.get_state(pid) == %{total: 10}
    end
  end

  describe "reset/2" do
    test "resets to initial state" do
      {:ok, pid} = State.start_link(%{count: 0})

      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end

      State.dispatch(pid, {:increment, 5}, reducer)
      State.dispatch(pid, {:increment, 3}, reducer)
      assert State.get_state(pid) == %{count: 8}

      State.reset(pid, %{count: 0})
      assert State.get_state(pid) == %{count: 0}
    end

    test "resets to custom initial state" do
      {:ok, pid} = State.start_link(%{count: 0, user: nil})

      State.put(pid, :count, 10)
      State.put(pid, :user, "Alice")
      assert State.get_state(pid) == %{count: 10, user: "Alice"}

      State.reset(pid, %{count: 5, user: "Bob"})
      assert State.get_state(pid) == %{count: 5, user: "Bob"}
    end
  end

  describe "edge cases and error handling" do
    test "handles empty state" do
      {:ok, pid} = State.start_link(%{})

      reducer = fn state, {:set, key, value} -> Map.put(state, key, value) end

      State.dispatch(pid, {:set, :test, "value"}, reducer)
      assert State.get_state(pid) == %{test: "value"}
    end

    test "handles nil state" do
      {:ok, pid} = State.start_link(nil)

      reducer = fn state, _action -> state end
      State.dispatch(pid, :noop, reducer)

      assert State.get_state(pid) == nil
    end

    test "handles atomic values" do
      {:ok, pid} = State.start_link(0)

      reducer = fn state, {:add, val} -> state + val end

      State.dispatch(pid, {:add, 5}, reducer)
      assert State.get_state(pid) == 5
    end

    test "handles list state" do
      {:ok, pid} = State.start_link([])

      reducer = fn state, {:push, item} -> [item | state] end

      State.dispatch(pid, {:push, "item1"}, reducer)
      State.dispatch(pid, {:push, "item2"}, reducer)

      assert State.get_state(pid) == ["item2", "item1"]
    end
  end

  describe "integration with Redux module" do
    test "works with Redux state structure" do
      {:ok, pid} = State.start_link(%{redux: nil})

      # This tests the interaction pattern
      redux = Phoenix.SessionProcess.Redux.init_state(%{count: 0})
      reducer = fn state, {:increment, val} -> %{state | count: state.count + val} end

      new_redux = Phoenix.SessionProcess.Redux.dispatch(redux, {:increment, 5}, reducer)
      State.update_state(pid, fn _ -> %{redux: new_redux} end)

      state = State.get_state(pid)
      assert Phoenix.SessionProcess.Redux.current_state(state.redux).count == 5
    end
  end
end
