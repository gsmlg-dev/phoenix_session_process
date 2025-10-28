defmodule Phoenix.SessionProcess.Redux do
  @moduledoc """
  Redux-style state management for Phoenix Session Process.

  This module provides a predictable state container with actions and reducers,
  similar to the Redux pattern from JavaScript. It enables:

  - Predictable state updates through actions and reducers
  - Subscriptions for reactive state management
  - Selectors with memoization for efficient derived state
  - Time-travel debugging capabilities
  - Middleware support for cross-cutting concerns
  - Phoenix.PubSub integration for distributed state notifications
  - LiveView integration with automatic assign updates
  - Action history and replay
  - Comprehensive telemetry events

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
    alias Phoenix.SessionProcess.Redux

    @impl true
    def init(_args) do
      redux = Redux.init_state(%{count: 0, user: nil})
      {:ok, %{redux: redux}}
    end

    def handle_call({:dispatch, action}, _from, state) do
      new_redux = Redux.dispatch(state.redux, action, &reducer/2)
      {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
    end

    def handle_call(:get_redux_state, _from, state) do
      {:reply, {:ok, state.redux}, state}
    end

    defp reducer(state, action) do
      case action do
        {:increment, value} -> %{state | count: state.count + value}
        {:set_user, user} -> %{state | user: user}
        _ -> state
      end
    end
  end
  ```

  ## Using Subscriptions

  ```elixir
  # Subscribe to state changes
  redux = Redux.subscribe(redux, fn state ->
    IO.inspect(state, label: "State changed")
  end)

  # Subscribe with selector (only notifies when user changes)
  user_selector = fn state -> state.user end
  redux = Redux.subscribe(redux, user_selector, fn user ->
    IO.inspect(user, label: "User changed")
  end)
  ```

  ## Using Selectors

  ```elixir
  alias Phoenix.SessionProcess.Redux.Selector

  # Create memoized selector
  expensive_selector = Selector.create_selector(
    [fn state -> state.items end, fn state -> state.filter end],
    fn items, filter ->
      Enum.filter(items, &(&1.type == filter))
    end
  )

  # Use selector
  filtered = Selector.select(redux, expensive_selector)
  ```

  ## LiveView Integration

  ```elixir
  defmodule MyAppWeb.DashboardLive do
    use Phoenix.LiveView
    alias Phoenix.SessionProcess.Redux.LiveView, as: ReduxLV

    def mount(_params, %{"session_id" => session_id}, socket) do
      # Auto-update assigns from Redux
      socket = ReduxLV.assign_from_session(socket, session_id, %{
        user: fn state -> state.user end,
        count: fn state -> state.count end
      })

      {:ok, assign(socket, session_id: session_id)}
    end

    def handle_info({:redux_assign_update, key, value}, socket) do
      {:noreply, ReduxLV.handle_assign_update(socket, key, value)}
    end
  end
  ```

  ## PubSub for Distributed State

  ```elixir
  # Initialize with PubSub
  redux = Redux.init_state(%{data: %{}},
    pubsub: MyApp.PubSub,
    pubsub_topic: "session:123"
  )

  # Dispatches will automatically broadcast via PubSub
  redux = Redux.dispatch(redux, {:update_data, %{key: "value"}}, &reducer/2)

  # Subscribe to broadcasts from other nodes
  unsubscribe = Redux.subscribe_to_broadcasts(
    MyApp.PubSub,
    "session:123",
    fn message -> IO.inspect(message) end
  )
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
    :max_history_size,
    :pubsub,
    :pubsub_topic,
    subscriptions: []
  ]

  @doc """
  Initialize a new Redux state.

  ## Options

  - `:reducer` - The reducer function to use
  - `:middleware` - List of middleware functions
  - `:max_history_size` - Maximum history entries (default: 100)
  - `:pubsub` - Phoenix.PubSub module name for distributed notifications
  - `:pubsub_topic` - Topic name for broadcasts (default: "redux:state_changes")

  ## Examples

      # Basic usage
      iex> redux = Redux.init_state(%{count: 0})
      iex> Redux.current_state(redux)
      %{count: 0}

      # With PubSub for distributed notifications
      iex> redux = Redux.init_state(%{count: 0},
      ...>   pubsub: MyApp.PubSub,
      ...>   pubsub_topic: "session:123:state"
      ...> )
  """
  @spec init_state(state(), keyword()) :: %__MODULE__{}
  def init_state(initial_state, opts \\ []) do
    %__MODULE__{
      current_state: initial_state,
      initial_state: initial_state,
      history: [],
      reducer: Keyword.get(opts, :reducer, nil),
      middleware: Keyword.get(opts, :middleware, []),
      max_history_size: Keyword.get(opts, :max_history_size, 100),
      pubsub: Keyword.get(opts, :pubsub, nil),
      pubsub_topic: Keyword.get(opts, :pubsub_topic, "redux:state_changes")
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

    new_redux = %{redux | current_state: new_state, history: new_history}

    # Notify subscriptions of state change
    new_redux = notify_subscriptions(new_redux)

    # Broadcast via PubSub if configured
    broadcast_state_change(new_redux, action)

    new_redux
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
  Alias for current_state/1. Used by Redux.Selector.

  ## Examples

      iex> redux = Redux.init_state(%{count: 0})
      iex> Redux.get_state(redux)
      %{count: 0}
  """
  @spec get_state(%__MODULE__{}) :: state()
  def get_state(redux), do: current_state(redux)

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
    new_redux = %{redux | current_state: redux.initial_state, history: []}
    # Notify subscriptions of state change
    notify_subscriptions(new_redux)
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
        if redux.reducer do
          redux.reducer.(acc_state, action)
        else
          raise "No reducer function defined for time travel. " <>
                  "Initialize Redux with a reducer: Redux.init_state(state, reducer: &my_reducer/2)"
        end
      end)

    new_redux = %{
      redux
      | current_state: target_state,
        history: Enum.drop(redux.history, steps_back)
    }

    # Notify subscriptions of state change
    notify_subscriptions(new_redux)
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
  Subscribe to state changes.

  See `Phoenix.SessionProcess.Redux.Subscription` for details.

  ## Examples

      # Subscribe to all changes
      redux = Redux.subscribe(redux, fn state ->
        IO.inspect(state, label: "State changed")
      end)

      # Subscribe with selector
      redux = Redux.subscribe(redux, fn state -> state.user end, fn user ->
        IO.inspect(user, label: "User changed")
      end)

  """
  @spec subscribe(%__MODULE__{}, function()) :: %__MODULE__{}
  @spec subscribe(%__MODULE__{}, function(), function()) :: %__MODULE__{}
  def subscribe(redux, selector_or_callback, callback \\ nil) do
    alias Phoenix.SessionProcess.Redux.Subscription

    {selector, callback} =
      if callback do
        {selector_or_callback, callback}
      else
        {nil, selector_or_callback}
      end

    {redux, _sub_id} = Subscription.subscribe_to_struct(redux, selector, callback)
    redux
  end

  @doc """
  Unsubscribe from state changes.

  ## Examples

      {redux, sub_id} = Redux.Subscription.subscribe_to_struct(redux, nil, callback)
      redux = Redux.unsubscribe(redux, sub_id)

  """
  @spec unsubscribe(%__MODULE__{}, reference()) :: %__MODULE__{}
  def unsubscribe(redux, subscription_id) do
    alias Phoenix.SessionProcess.Redux.Subscription
    Subscription.unsubscribe_from_struct(redux, subscription_id)
  end

  @doc """
  Notify all subscriptions of state changes.

  This is automatically called by `dispatch/2` and `dispatch/3`,
  but can be called manually if needed.

  ## Examples

      redux = Redux.notify_subscriptions(redux)

  """
  @spec notify_subscriptions(%__MODULE__{}) :: %__MODULE__{}
  def notify_subscriptions(redux) do
    alias Phoenix.SessionProcess.Redux.Subscription
    Subscription.notify_all_struct(redux)
  end

  @doc """
  Enable PubSub broadcasting for a Redux store.

  ## Examples

      redux = Redux.init_state(%{count: 0})
      redux = Redux.enable_pubsub(redux, MyApp.PubSub, "session:123")

  """
  @spec enable_pubsub(%__MODULE__{}, module(), String.t()) :: %__MODULE__{}
  def enable_pubsub(redux, pubsub_module, topic) do
    %{redux | pubsub: pubsub_module, pubsub_topic: topic}
  end

  @doc """
  Disable PubSub broadcasting for a Redux store.

  ## Examples

      redux = Redux.disable_pubsub(redux)

  """
  @spec disable_pubsub(%__MODULE__{}) :: %__MODULE__{}
  def disable_pubsub(redux) do
    %{redux | pubsub: nil, pubsub_topic: nil}
  end

  @doc """
  Manually broadcast a state change via PubSub.

  Usually called automatically by dispatch, but can be called manually if needed.

  ## Examples

      Redux.broadcast_state_change(redux, {:custom_action})

  """
  @spec broadcast_state_change(%__MODULE__{}, action()) :: :ok
  def broadcast_state_change(%{pubsub: nil}, _action), do: :ok

  def broadcast_state_change(%{pubsub: pubsub, pubsub_topic: topic} = redux, action) do
    message = %{
      action: action,
      state: redux.current_state,
      timestamp: System.system_time(:millisecond)
    }

    Phoenix.PubSub.broadcast(pubsub, topic, {:redux_state_change, message})
  end

  @doc """
  Subscribe to PubSub broadcasts from other Redux stores.

  This allows you to listen to state changes from other processes or nodes.

  Returns a function to unsubscribe.

  ## Examples

      # In a LiveView process
      unsubscribe = Redux.subscribe_to_broadcasts(
        MyApp.PubSub,
        "session:123",
        fn message ->
          # Handle remote state change
          send(self(), {:remote_state_change, message})
        end
      )

      # Later, unsubscribe
      unsubscribe.()

  """
  @spec subscribe_to_broadcasts(module(), String.t(), (map() -> any())) :: (-> :ok)
  def subscribe_to_broadcasts(pubsub_module, topic, callback) do
    Phoenix.PubSub.subscribe(pubsub_module, topic)

    # Store callback in process dictionary
    callbacks = Process.get(:redux_pubsub_callbacks, %{})
    ref = make_ref()
    Process.put(:redux_pubsub_callbacks, Map.put(callbacks, ref, callback))

    # Start message handler if not already started
    unless Process.get(:redux_pubsub_handler_started) do
      spawn_link(fn -> pubsub_message_handler() end)
      Process.put(:redux_pubsub_handler_started, true)
    end

    # Return unsubscribe function
    fn ->
      callbacks = Process.get(:redux_pubsub_callbacks, %{})
      Process.put(:redux_pubsub_callbacks, Map.delete(callbacks, ref))
      :ok
    end
  end

  # Private function to handle PubSub messages
  defp pubsub_message_handler do
    receive do
      {:redux_state_change, message} ->
        callbacks = Process.get(:redux_pubsub_callbacks, %{})

        Enum.each(callbacks, fn {_ref, callback} ->
          try do
            callback.(message)
          rescue
            error ->
              require Logger

              Logger.error(
                "Redux PubSub callback error: #{inspect(error)}\n" <>
                  Exception.format_stacktrace(__STACKTRACE__)
              )
          end
        end)

        pubsub_message_handler()

      _ ->
        pubsub_message_handler()
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
