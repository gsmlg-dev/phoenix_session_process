defmodule Phoenix.SessionProcess.Redux do
  @moduledoc """
  > #### Deprecation Notice {: .warning}
  >
  > **This module is deprecated as of v0.6.0 and will be removed in v1.0.0**
  >
  > The Redux functionality has been integrated directly into `Phoenix.SessionProcess`.
  > You no longer need to manage a separate Redux struct - SessionProcess IS the Redux store.
  >
  > **Migration Guide:**
  >
  > ```elixir
  > # OLD (deprecated):
  > def init(_args) do
  >   redux = Redux.init_state(%{count: 0}, pubsub: MyApp.PubSub, pubsub_topic: "session:123:redux")
  >   {:ok, %{redux: redux}}
  > end
  >
  > def handle_call({:dispatch, action}, _from, state) do
  >   new_redux = Redux.dispatch(state.redux, action, &reducer/2)
  >   {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
  > end
  >
  > # NEW (recommended):
  > def user_init(_args) do
  >   %{count: 0}  # Just return your state
  > end
  >
  > def init(args) do
  >   # SessionProcess macro handles Redux setup automatically
  >   super(args)
  > end
  >
  > # Then use the new API:
  > SessionProcess.dispatch(session_id, action)
  > SessionProcess.subscribe(session_id, selector)
  > ```
  >
  > See `Phoenix.SessionProcess` for the new API documentation and `REDUX_TO_SESSIONPROCESS_MIGRATION.md` for detailed migration examples.

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

  ## Using Subscriptions (New Message-Based API)

  ```elixir
  # Subscribe to state changes - receives messages
  {:ok, sub_id, redux} = Redux.subscribe(
    redux,
    fn state -> state.user end,
    self(),
    :user_updated
  )

  # Immediately receive current value
  receive do
    {:user_updated, user} -> IO.puts("Current: \#{inspect(user)}")
  end

  # Receive updates when user changes
  receive do
    {:user_updated, new_user} -> IO.puts("Updated: \#{inspect(new_user)}")
  end

  # Unsubscribe
  {:ok, redux} = Redux.unsubscribe(redux, sub_id)
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

  @type t :: %__MODULE__{
          current_state: state(),
          initial_state: state(),
          history: list({action(), state()}),
          reducer: reducer() | nil,
          middleware: list(middleware()),
          max_history_size: non_neg_integer(),
          pubsub: module() | nil,
          pubsub_topic: binary() | nil,
          subscriptions: list(map())
        }

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

  # Private helper to log deprecation warnings
  defp log_deprecation(function_name, migration_message) do
    require Logger

    Logger.warning("""
    [Phoenix.SessionProcess.Redux] DEPRECATION WARNING
    Function: Redux.#{function_name}
    Status: This module is deprecated as of v0.6.0 and will be removed in v1.0.0

    Migration: #{migration_message}

    See REDUX_TO_SESSIONPROCESS_MIGRATION.md for detailed examples.
    """)
  end

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
  @deprecated "Use Phoenix.SessionProcess's built-in Redux functionality via user_init/1 callback instead"
  @spec init_state(state(), keyword()) :: %__MODULE__{}
  def init_state(initial_state, opts \\ []) do
    log_deprecation(
      "init_state/2",
      "Define user_init/1 callback in your SessionProcess module that returns initial state directly"
    )

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
  @deprecated "Use Phoenix.SessionProcess.dispatch(session_id, action) instead"
  @spec dispatch(%__MODULE__{}, action(), reducer()) :: %__MODULE__{}
  def dispatch(redux, action, reducer) when is_function(reducer, 2) do
    log_deprecation(
      "dispatch/3",
      "Use Phoenix.SessionProcess.dispatch(session_id, action) and register reducers via register_reducer/3"
    )

    apply_action(redux, action, reducer)
  end

  @doc """
  Dispatch an action using the built-in reducer.

  Requires the Redux module to implement the reducer/2 callback.
  """
  @deprecated "Use Phoenix.SessionProcess.dispatch(session_id, action) instead"
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

  Supports both new message-based API and legacy callback API:

  **New Message-Based API** (recommended):
  - `subscribe(redux, selector)` - Subscribe with selector, returns `{:ok, sub_id, redux}`
  - `subscribe(redux, selector, pid, event_name)` - Full control

  **Legacy Callback API** (deprecated):
  - `subscribe(redux, callback)` - Subscribe with callback function
  - `subscribe(redux, selector, callback)` - Subscribe with selector and callback

  ## New API Examples

      # Subscribe with selector - returns {:ok, sub_id, redux}
      {:ok, sub_id, redux} = Redux.subscribe(redux, fn state -> state.user end)

      # Immediately receives current user
      receive do
        {:state_updated, user} -> IO.puts("Current: \#{inspect(user)}")
      end

      # With custom event name
      {:ok, sub_id, redux} = Redux.subscribe(
        redux,
        fn state -> state.count end,
        self(),
        :count_changed
      )

  ## Legacy API Examples

      # Old callback style (still works)
      redux = Redux.subscribe(redux, fn state ->
        IO.inspect(state, label: "State")
      end)

      # With selector
      redux = Redux.subscribe(redux, fn s -> s.user end, fn user ->
        IO.puts("User: \#{inspect(user)}")
      end)

  """
  @deprecated "Use Phoenix.SessionProcess.subscribe(session_id, selector, event_name, pid) instead"
  @spec subscribe(%__MODULE__{}, function()) :: %__MODULE__{}
  def subscribe(redux, callback) when is_function(callback, 1) do
    log_deprecation(
      "subscribe/2",
      "Use Phoenix.SessionProcess.subscribe(session_id, selector, event_name) for message-based subscriptions"
    )

    alias Phoenix.SessionProcess.Redux.Subscription

    # Legacy API: subscribe(redux, callback) - assumes callback, not selector
    # This maintains backward compatibility where subscribe/2 returns redux
    {redux, _sub_id} = Subscription.subscribe_to_struct(redux, nil, callback)
    redux
  end

  @spec subscribe(%__MODULE__{}, function(), pid() | function()) ::
          {:ok, reference(), %__MODULE__{}} | %__MODULE__{}
  def subscribe(redux, selector, pid_or_callback) do
    alias Phoenix.SessionProcess.Redux.Subscription

    cond do
      # Legacy API: subscribe(redux, selector, callback)
      is_function(pid_or_callback, 1) ->
        {redux, _sub_id} = Subscription.subscribe_to_struct(redux, selector, pid_or_callback)
        redux

      # New API: subscribe(redux, selector, pid)
      is_pid(pid_or_callback) ->
        Subscription.subscribe(redux, selector, pid_or_callback, :state_updated)

      true ->
        raise ArgumentError,
              "Third argument must be either a callback function or a PID"
    end
  end

  @spec subscribe(%__MODULE__{}, function(), pid(), atom()) ::
          {:ok, reference(), %__MODULE__{}}
  def subscribe(redux, selector, pid, event_name)
      when is_function(selector) and is_pid(pid) and is_atom(event_name) do
    alias Phoenix.SessionProcess.Redux.Subscription
    Subscription.subscribe(redux, selector, pid, event_name)
  end

  @doc """
  Subscribe to state changes with callback (legacy API).

  **DEPRECATED**: Use `subscribe/4` instead for message-based notifications.

  ## Examples

      # Subscribe to all changes
      redux = Redux.subscribe_callback(redux, fn state ->
        IO.inspect(state, label: "State changed")
      end)

      # Subscribe with selector
      redux = Redux.subscribe_callback(redux, fn state -> state.user end, fn user ->
        IO.inspect(user, label: "User changed")
      end)

  """
  @spec subscribe_callback(%__MODULE__{}, function()) :: %__MODULE__{}
  def subscribe_callback(redux, callback) when is_function(callback, 1) do
    alias Phoenix.SessionProcess.Redux.Subscription
    {redux, _sub_id} = Subscription.subscribe_to_struct(redux, nil, callback)
    redux
  end

  @spec subscribe_callback(%__MODULE__{}, function() | map(), function()) :: %__MODULE__{}
  def subscribe_callback(redux, selector, callback) when is_function(callback, 1) do
    alias Phoenix.SessionProcess.Redux.Subscription
    {redux, _sub_id} = Subscription.subscribe_to_struct(redux, selector, callback)
    redux
  end

  @doc """
  Unsubscribe from state changes by subscription ID.

  Returns updated Redux struct for backward compatibility.

  ## Examples

      {:ok, sub_id, redux} = Redux.subscribe(redux, selector)
      redux = Redux.unsubscribe(redux, sub_id)

      # Or with legacy subscribe API
      {redux, sub_id} = Subscription.subscribe_to_struct(redux, nil, callback)
      redux = Redux.unsubscribe(redux, sub_id)

  """
  @spec unsubscribe(%__MODULE__{}, reference()) :: %__MODULE__{}
  def unsubscribe(redux, subscription_id) do
    alias Phoenix.SessionProcess.Redux.Subscription
    {:ok, updated_redux} = Subscription.unsubscribe(redux, subscription_id)
    updated_redux
  end

  @doc """
  Unsubscribe all subscriptions for a given PID.

  Returns updated Redux struct.

  ## Examples

      redux = Redux.unsubscribe_all(redux, self())

  """
  @spec unsubscribe_all(%__MODULE__{}, pid()) :: %__MODULE__{}
  def unsubscribe_all(redux, pid) do
    alias Phoenix.SessionProcess.Redux.Subscription
    {:ok, updated_redux} = Subscription.unsubscribe_all(redux, pid)
    updated_redux
  end

  @doc """
  Remove subscriptions for a dead process by monitor reference.

  This should be called from handle_info when receiving :DOWN messages.

  ## Examples

      def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
        redux = Redux.remove_subscription_by_monitor(state.redux, ref)
        {:noreply, %{state | redux: redux}}
      end

  """
  @spec remove_subscription_by_monitor(%__MODULE__{}, reference()) :: %__MODULE__{}
  def remove_subscription_by_monitor(redux, monitor_ref) do
    alias Phoenix.SessionProcess.Redux.Subscription
    Subscription.remove_by_monitor(redux, monitor_ref)
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
