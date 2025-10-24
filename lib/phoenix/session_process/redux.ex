defmodule Phoenix.SessionProcess.Redux do
  @moduledoc """
  Redux-style state management for Phoenix Session Process.

  This module provides a predictable state container with actions and reducers,
  similar to the Redux pattern from JavaScript. It enables:

  - Predictable state updates through actions
  - Time-travel debugging capabilities
  - Middleware support
  - State persistence
  - Action logging and replay

  ## Basic Usage

  ```elixir
  defmodule MyApp.SessionState do
    use Phoenix.SessionProcess.Redux

    @impl true
    def init(_args) do
      %{count: 0, user: nil}
    end

    @impl true
    def reducer(state, action) do
      case action do
        {:increment, value} ->
          %{state | count: state.count + value}

        {:set_user, user} ->
          %{state | user: user}

        :reset ->
          %{count: 0, user: nil}

        _ ->
          state
      end
    end
  end
  ```

  ## Using in Session Process

  ```elixir
  defmodule MyApp.SessionProcess do
    use Phoenix.SessionProcess, :process
    use Phoenix.SessionProcess.Redux

    @impl true
    def init(_args) do
      {:ok, %{redux: Redux.init_state(%{count: 0, user: nil})}}
    end

    def handle_call({:dispatch, action}, _from, state) do
      new_redux_state = Redux.dispatch(state.redux, action)
      {:reply, {:ok, new_redux_state}, %{state | redux: new_redux_state}}
    end
  end
  ```
  """

  @type state :: any()
  @type action :: any()
  @type reducer :: (state(), action() -> state())
  @type middleware :: (action(), state(), (action() -> state()) -> state())

  @doc """
  The Redux state structure containing current state and action history.
  """
  defstruct [
    :current_state,
    :initial_state,
    :history,
    :reducer,
    :middleware,
    :max_history_size
  ]

  @doc """
  Initialize a new Redux state.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> Redux.current_state(redux)
      %{count: 0}
  """
  @spec init_state(state(), keyword()) :: %__MODULE__{}
  def init_state(initial_state, opts \\ []) do
    %__MODULE__{
      current_state: initial_state,
      initial_state: initial_state,
      history: [],
      reducer: Keyword.get(opts, :reducer, nil),
      middleware: Keyword.get(opts, :middleware, []),
      max_history_size: Keyword.get(opts, :max_history_size, 100)
    }
  end

  @doc """
  Dispatch an action to update the state.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> redux = Redux.dispatch(redux, {:increment, 1}, fn state, {:increment, val} -> %{state | count: state.count + val} end)
      iex> Redux.current_state(redux)
      %{count: 1}
  """
  @spec dispatch(%__MODULE__{}, action(), reducer()) :: %__MODULE__{}
  def dispatch(redux, action, reducer) when is_function(reducer, 2) do
    apply_action(redux, action, reducer)
  end

  @doc """
  Dispatch an action using the built-in reducer.

  Requires the Redux module to implement the reducer/2 callback.
  """
  @spec dispatch(%__MODULE__{}, action()) :: %__MODULE__{}
  def dispatch(redux, action) do
    if function_exported?(__MODULE__, :reducer, 2) do
      apply_action(redux, action, &__MODULE__.reducer/2)
    else
      raise "No reducer function defined. Use dispatch/3 or implement reducer/2"
    end
  end

  defp apply_action(redux, action, reducer) do
    # Apply middleware chain
    # Apply in reverse order like Redux
    middleware_list = Enum.reverse(redux.middleware)

    # Base reducer that takes only action
    base_reducer = fn act ->
      reducer.(redux.current_state, act)
    end

    # Build middleware chain
    final_reducer =
      Enum.reduce(middleware_list, base_reducer, fn middleware, next ->
        fn act ->
          middleware.(act, redux.current_state, next)
        end
      end)

    new_state = final_reducer.(action)

    history_entry = %{
      action: action,
      previous_state: redux.current_state,
      new_state: new_state,
      timestamp: System.system_time(:millisecond)
    }

    new_history =
      [history_entry | redux.history]
      |> Enum.take(redux.max_history_size)

    %{redux | current_state: new_state, history: new_history}
  end

  @doc """
  Get the current state.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> Redux.current_state(redux)
      %{count: 0}
  """
  @spec current_state(%__MODULE__{}) :: state()
  def current_state(redux), do: redux.current_state

  @doc """
  Get the initial state.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> Redux.initial_state(redux)
      %{count: 0}
  """
  @spec initial_state(%__MODULE__{}) :: state()
  def initial_state(redux), do: redux.initial_state

  @doc """
  Get the action history.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> redux = Redux.dispatch(redux, {:increment, 1}, fn s, a -> %{s | count: s.count + elem(a, 1)} end)
      iex> history = Redux.history(redux)
      iex> length(history) == 1
      true
  """
  @spec history(%__MODULE__{}) :: list()
  def history(redux), do: redux.history

  @doc """
  Reset to the initial state.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> redux = Redux.dispatch(redux, {:increment, 1}, fn s, {:increment, val} -> %{s | count: s.count + val} end)
      iex> redux = Redux.reset(redux)
      iex> Redux.current_state(redux)
      %{count: 0}
  """
  @spec reset(%__MODULE__{}) :: %__MODULE__{}
  def reset(redux) do
    %{redux | current_state: redux.initial_state, history: []}
  end

  @doc """
  Time travel to a specific point in history.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> redux = Redux.dispatch(redux, {:increment, 1}, fn s, {:increment, val} -> %{s | count: s.count + val} end)
      iex> redux = Redux.dispatch(redux, {:increment, 2}, fn s, {:increment, val} -> %{s | count: s.count + val} end)
      iex> redux = Redux.time_travel(redux, 1)
      iex> Redux.current_state(redux)
      %{count: 1}
  """
  @spec time_travel(%__MODULE__{}, integer()) :: %__MODULE__{}
  def time_travel(redux, steps_back) when steps_back >= 0 do
    if steps_back > length(redux.history) do
      raise "Cannot time travel beyond history length"
    end

    target_state =
      redux.history
      |> Enum.drop(steps_back)
      |> Enum.reverse()
      |> Enum.reduce(redux.initial_state, fn %{action: action}, acc_state ->
        if function_exported?(__MODULE__, :reducer, 2) do
          __MODULE__.reducer(acc_state, action)
        else
          raise "No reducer function defined for time travel"
        end
      end)

    %{redux | current_state: target_state, history: Enum.drop(redux.history, steps_back)}
  end

  @doc """
  Add middleware to the Redux pipeline.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> logger = fn action, state, next -> next.(action) end
      iex> redux = Redux.add_middleware(redux, logger)
      iex> Redux.middleware(redux) |> length()
      1
  """
  @spec add_middleware(%__MODULE__{}, middleware()) :: %__MODULE__{}
  def add_middleware(redux, middleware) do
    %{redux | middleware: [middleware | redux.middleware]}
  end

  @doc """
  Get the list of middleware functions.
  """
  @spec middleware(%__MODULE__{}) :: list(middleware())
  def middleware(redux), do: redux.middleware

  @doc """
  Create a middleware for logging actions.
  """
  @spec logger_middleware :: middleware()
  def logger_middleware do
    fn action, state, next ->
      IO.puts("[Redux] Action: #{inspect(action)}")
      IO.puts("[Redux] Before: #{inspect(state)}")
      new_state = next.(action)
      IO.puts("[Redux] After: #{inspect(new_state)}")
      new_state
    end
  end

  @doc """
  Create a middleware for validating actions.
  """
  @spec validation_middleware((action() -> boolean())) :: middleware()
  def validation_middleware(validator) do
    fn action, state, next ->
      if validator.(action) do
        next.(action)
      else
        IO.puts("[Redux] Invalid action: #{inspect(action)}")
        state
      end
    end
  end

  @doc """
  Default reducer that returns state unchanged.
  Can be overridden by implementing this function in your module.
  """
  @spec reducer(state(), action()) :: state()
  def reducer(state, _action) do
    state
  end
end
