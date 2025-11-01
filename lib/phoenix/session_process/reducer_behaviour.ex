defmodule Phoenix.SessionProcess.ReducerBehaviour do
  @moduledoc """
  Defines the behaviour for reducers in Phoenix.SessionProcess.

  Reducers are modules that manage a slice of the session state using Redux-style
  state updates. Each reducer handles actions and returns updated state.

  ## Required Callbacks

  - `init_state/0` - Initialize the reducer's state slice (required)
  - `handle_action/2` - Handle synchronous actions (required)

  ## Optional Callbacks

  - `handle_async/3` - Handle asynchronous actions (optional)
  - `handle_unmatched_action/2` - Handle actions that don't match any pattern (optional)
  - `handle_unmatched_async/3` - Handle async actions that don't match any pattern (optional)

  ## Usage

  To create a reducer, use the `:reducer` macro:

      defmodule MyApp.CounterReducer do
        use Phoenix.SessionProcess, :reducer

        @name :counter
        @action_prefix "counter"

        @impl true
        def init_state do
          %{count: 0}
        end

        @impl true
        def handle_action(action, state) do
          alias Phoenix.SessionProcess.Action

          case action do
            %Action{type: "increment"} ->
              %{state | count: state.count + 1}

            %Action{type: "set", payload: value} ->
              %{state | count: value}

            _ ->
              handle_unmatched_action(action, state)
          end
        end

        # Optional: Handle async actions
        @impl true
        def handle_async(action, dispatch, state) do
          alias Phoenix.SessionProcess.Action

          case action do
            %Action{type: "fetch_data", payload: url} ->
              task = Task.async(fn ->
                data = HTTPClient.get(url)
                dispatch.("counter.data_received", data)
              end)

              fn ->
                Task.shutdown(task, :brutal_kill)
                :ok
              end

            _ ->
              handle_unmatched_async(action, dispatch, state)
          end
        end
      end

  ## Module Attributes

  - `@name` - Atom identifying the reducer and its state slice (required, must be atom)
  - `@action_prefix` - Binary prefix for action routing (optional, defaults to stringified name)

  ## State Slicing

  Each reducer manages a slice of the session state identified by `@name`:

      # Full session state
      %{
        counter: %{count: 5},    # CounterReducer's slice (if @name is :counter)
        user: %{current: nil}    # UserReducer's slice (if @name is :user)
      }

  ## Action Routing

  Actions are routed to reducers based on `@action_prefix`:

      # With @action_prefix "counter"
      dispatch(session_id, "counter.increment")  # Routes to CounterReducer
      dispatch(session_id, "user.set", user)     # Routes to UserReducer (if exists)

  ## Type Constraints

  - Reducer `@name` MUST be an atom (compile-time enforced)
  - Action types MUST be binary strings (runtime enforced)
  - Reducer `@action_prefix` MUST be binary, nil, or "" (compile-time enforced)
  """

  alias Phoenix.SessionProcess.Action

  @doc """
  Initialize the reducer's state slice.

  Called once when the reducer is registered. Should return the initial state
  for this reducer's slice of the session state.

  ## Returns

  - `map()` - Initial state for this reducer's slice

  ## Examples

      def init_state do
        %{count: 0, last_update: nil}
      end

      def init_state do
        %{users: [], loading: false, error: nil}
      end
  """
  @callback init_state() :: map()

  @doc """
  Handle synchronous actions.

  Called for each action dispatched to the session. Should pattern match on the
  action and return updated state. If the action doesn't match, delegate to
  `handle_unmatched_action/2`.

  ## Parameters

  - `action` - Action struct with type (binary), payload (any), and meta (map)
  - `state` - Current state slice for this reducer

  ## Returns

  - `map()` - Updated state for this reducer's slice

  ## Examples

      def handle_action(action, state) do
        alias Phoenix.SessionProcess.Action

        case action do
          %Action{type: "increment"} ->
            %{state | count: state.count + 1}

          %Action{type: "set", payload: value} ->
            %{state | count: value}

          _ ->
            handle_unmatched_action(action, state)
        end
      end
  """
  @callback handle_action(action :: Action.t(), state :: map()) :: map()

  @doc """
  Handle asynchronous actions (optional).

  Called for async actions that match this reducer's action prefix. Must return
  a cancellation callback function. If not implemented, async actions will not
  be processed by this reducer.

  ## Parameters

  - `action` - Action struct with type (binary), payload (any), and meta (map)
  - `dispatch` - Function to dispatch new actions: `dispatch(type, payload, meta)`
  - `state` - Current state slice for this reducer

  ## Returns

  - `(() -> any())` - Cancellation callback function

  ## Examples

      def handle_async(action, dispatch, state) do
        alias Phoenix.SessionProcess.Action

        case action do
          %Action{type: "fetch_user", payload: user_id} ->
            task = Task.async(fn ->
              user = MyApp.Users.get(user_id)
              dispatch.("user.set", user, [])
            end)

            fn ->
              Task.shutdown(task, :brutal_kill)
              :ok
            end

          _ ->
            handle_unmatched_async(action, dispatch, state)
        end
      end
  """
  @callback handle_async(
              action :: Action.t(),
              dispatch :: (binary(), any(), keyword() -> any()),
              state :: map()
            ) :: (-> any())

  @doc """
  Handle unmatched actions (optional).

  Called when an action doesn't match any pattern in `handle_action/2`. Default
  implementation logs a debug message suggesting use of `@action_prefix`. Override
  to customize behavior.

  ## Parameters

  - `action` - Action struct that didn't match
  - `state` - Current state slice for this reducer

  ## Returns

  - `map()` - State (typically unchanged)

  ## Examples

      def handle_unmatched_action(action, state) do
        MyApp.Metrics.track_unmatched_action(action)
        state
      end

      # Globally configure via config:
      config :phoenix_session_process,
        unmatched_action_handler: :warn  # :log | :warn | :silent | function/3
  """
  @callback handle_unmatched_action(action :: Action.t(), state :: map()) :: map()

  @doc """
  Handle unmatched asynchronous actions (optional).

  Called when an async action doesn't match any pattern in `handle_async/3`.
  Default implementation logs a debug message. Override to customize behavior.

  ## Parameters

  - `action` - Action struct that didn't match
  - `dispatch` - Function to dispatch new actions
  - `state` - Current state slice for this reducer

  ## Returns

  - `(() -> any())` - Cancellation callback (typically no-op: `fn -> nil end`)

  ## Examples

      def handle_unmatched_async(action, dispatch, state) do
        MyApp.Metrics.track_unmatched_async(action)
        fn -> nil end
      end
  """
  @callback handle_unmatched_async(
              action :: Action.t(),
              dispatch :: (binary(), any(), keyword() -> any()),
              state :: map()
            ) :: (-> any())

  @optional_callbacks handle_async: 3, handle_unmatched_action: 2, handle_unmatched_async: 3
end
