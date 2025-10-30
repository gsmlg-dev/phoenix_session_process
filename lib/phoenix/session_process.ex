defmodule Phoenix.SessionProcess do
  @moduledoc """
  Main API for managing isolated session processes in Phoenix applications.

  This module provides a high-level interface for creating, managing, and communicating
  with dedicated GenServer processes for each user session. Each session runs in its own
  isolated process, enabling real-time session state management without external dependencies.

  ## Features

  - **Session Isolation**: Each user session runs in a dedicated GenServer process
  - **Automatic Cleanup**: TTL-based session expiration and garbage collection
  - **LiveView Integration**: Built-in support for monitoring LiveView processes
  - **High Performance**: 10,000+ sessions/second creation rate
  - **Zero Dependencies**: No Redis, databases, or external services required
  - **Comprehensive Telemetry**: Built-in observability for all operations

  ## Quick Start

  ### 1. Add to Supervision Tree

  Add the supervisor to your application's supervision tree in `lib/my_app/application.ex`:

      def start(_type, _args) do
        children = [
          # ... other children ...
          {Phoenix.SessionProcess.Supervisor, []}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  ### 2. Configure Session ID Generation

  Add the SessionId plug after `:fetch_session` in your router:

      pipeline :browser do
        plug :accepts, ["html"]
        plug :fetch_session
        plug Phoenix.SessionProcess.SessionId  # Add this
        # ... other plugs ...
      end

  ### 3. Use in Controllers and LiveViews

      defmodule MyAppWeb.PageController do
        use MyAppWeb, :controller

        def index(conn, _params) do
          session_id = conn.assigns.session_id

          # Start session process
          {:ok, _pid} = Phoenix.SessionProcess.start(session_id)

          # Store data
          Phoenix.SessionProcess.cast(session_id, {:put, :user_id, 123})

          # Retrieve data
          {:ok, state} = Phoenix.SessionProcess.call(session_id, :get_state)

          render(conn, "index.html", state: state)
        end
      end

  ## Configuration

  Configure the library in `config/config.exs`:

      config :phoenix_session_process,
        session_process: MyApp.SessionProcess,  # Default session module
        max_sessions: 10_000,                   # Maximum concurrent sessions
        session_ttl: 3_600_000,                # Session TTL (1 hour)
        rate_limit: 100                        # Sessions per minute

  ## Creating Custom Session Processes

  ### Basic Session Process

      defmodule MyApp.SessionProcess do
        use Phoenix.SessionProcess, :process

        @impl true
        def init(_init_arg) do
          {:ok, %{user_id: nil, cart: [], preferences: %{}}}
        end

        @impl true
        def handle_call(:get_user, _from, state) do
          {:reply, state.user_id, state}
        end

        @impl true
        def handle_cast({:set_user, user_id}, state) do
          {:noreply, %{state | user_id: user_id}}
        end
      end

  ### With LiveView Integration

      defmodule MyApp.SessionProcessWithLiveView do
        use Phoenix.SessionProcess, :process

        @impl true
        def init(_init_arg) do
          {:ok, %{user: nil}}
        end

        # Automatically monitors LiveView processes
        # Sends :session_expired message when session terminates
      end

  ## API Overview

  ### Session Management
  - `start/1`, `start/2`, `start/3` - Start session processes
  - `started?/1` - Check if session exists
  - `terminate/1` - Stop session process
  - `find_session/1` - Find session by ID

  ### Communication
  - `call/2`, `call/3` - Synchronous requests
  - `cast/2` - Asynchronous messages

  ### Inspection
  - `list_session/0` - List all sessions
  - `session_info/0` - Get session count and modules
  - `session_stats/0` - Get memory and performance stats
  - `list_sessions_by_module/1` - Filter sessions by module

  ## Error Handling

  All operations return structured error tuples:

      {:error, {:invalid_session_id, session_id}}
      {:error, {:session_limit_reached, max_sessions}}
      {:error, {:session_not_found, session_id}}
      {:error, {:timeout, timeout}}

  Use `Phoenix.SessionProcess.Error.message/1` for human-readable errors.

  ## Performance

  Expected performance metrics:
  - Session Creation: 10,000+ sessions/sec
  - Memory Usage: ~10KB per session
  - Registry Lookups: 100,000+ lookups/sec

  See the benchmarking guide at `bench/README.md` for details.
  """

  alias Phoenix.SessionProcess.{Cleanup, Config, ProcessSupervisor}
  alias Phoenix.SessionProcess.Registry, as: SessionRegistry

  @doc """
  Starts a session process using the default configured module.

  The session process is registered in the Registry and scheduled for automatic
  cleanup based on the configured TTL.

  ## Parameters
  - `session_id` - Unique binary identifier for the session

  ## Returns
  - `{:ok, pid}` - Session process started successfully
  - `{:error, {:already_started, pid}}` - Session already exists
  - `{:error, {:invalid_session_id, id}}` - Invalid session ID format
  - `{:error, {:session_limit_reached, max}}` - Maximum sessions exceeded

  ## Examples

      {:ok, pid} = Phoenix.SessionProcess.start("user_123")
      {:error, {:already_started, pid}} = Phoenix.SessionProcess.start("user_123")
  """
  @spec start(binary()) :: {:ok, pid()} | {:error, term()}
  defdelegate start(session_id), to: Phoenix.SessionProcess.ProcessSupervisor, as: :start_session

  @doc """
  Starts a session process using a custom module.

  This allows you to use a specific session process implementation instead of
  the default configured module.

  ## Parameters
  - `session_id` - Unique binary identifier for the session
  - `module` - Module implementing the session process behavior

  ## Returns
  - `{:ok, pid}` - Session process started successfully
  - `{:error, {:already_started, pid}}` - Session already exists
  - `{:error, {:invalid_session_id, id}}` - Invalid session ID format
  - `{:error, {:session_limit_reached, max}}` - Maximum sessions exceeded

  ## Examples

      {:ok, pid} = Phoenix.SessionProcess.start("user_123", MyApp.CustomSessionProcess)

      iex> result = Phoenix.SessionProcess.start("valid_session", Phoenix.SessionProcess.DefaultSessionProcess)
      iex> match?({:ok, _pid}, result) or match?({:error, {:already_started, _pid}}, result)
      true

      iex> Phoenix.SessionProcess.start("invalid@session", Phoenix.SessionProcess.DefaultSessionProcess)
      {:error, {:invalid_session_id, "invalid@session"}}
  """
  @spec start(binary(), atom()) :: {:ok, pid()} | {:error, term()}
  defdelegate start(session_id, module),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :start_session

  @doc """
  Starts a session process with a custom module and initialization arguments.

  The initialization arguments are passed to the module's `init/1` callback,
  allowing you to set up initial state or configuration.

  ## Parameters
  - `session_id` - Unique binary identifier for the session
  - `module` - Module implementing the session process behavior
  - `arg` - Initialization argument(s) passed to `init/1`

  ## Returns
  - `{:ok, pid}` - Session process started successfully
  - `{:error, {:already_started, pid}}` - Session already exists
  - `{:error, {:invalid_session_id, id}}` - Invalid session ID format
  - `{:error, {:session_limit_reached, max}}` - Maximum sessions exceeded

  ## Examples

      # With map argument
      {:ok, pid} = Phoenix.SessionProcess.start("user_123", MyApp.SessionProcess, %{user_id: 123})

      # With keyword list
      {:ok, pid} = Phoenix.SessionProcess.start("user_456", MyApp.SessionProcess, [debug: true])

      iex> result = Phoenix.SessionProcess.start("valid_session_with_args", Phoenix.SessionProcess.DefaultSessionProcess, %{user_id: 123})
      iex> match?({:ok, _pid}, result) or match?({:error, {:already_started, _pid}}, result)
      true

      iex> result = Phoenix.SessionProcess.start("valid_session_with_list", Phoenix.SessionProcess.DefaultSessionProcess, [debug: true])
      iex> match?({:ok, _pid}, result) or match?({:error, {:already_started, _pid}}, result)
      true
  """
  @spec start(binary(), atom(), any()) :: {:ok, pid()} | {:error, term()}
  defdelegate start(session_id, module, arg),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :start_session

  @doc """
  Checks if a session process is currently running.

  ## Parameters
  - `session_id` - Unique binary identifier for the session

  ## Returns
  - `true` - Session process exists and is running
  - `false` - Session process does not exist

  ## Examples

      {:ok, _pid} = Phoenix.SessionProcess.start("user_123")
      true = Phoenix.SessionProcess.started?("user_123")
      false = Phoenix.SessionProcess.started?("nonexistent")
  """
  @spec started?(binary()) :: boolean()
  defdelegate started?(session_id),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :session_process_started?

  @doc """
  Terminates a session process.

  This gracefully shuts down the session process and removes it from the Registry.
  Emits telemetry events for session stop.

  ## Parameters
  - `session_id` - Unique binary identifier for the session

  ## Returns
  - `:ok` - Session terminated successfully
  - `{:error, :not_found}` - Session does not exist

  ## Examples

      {:ok, _pid} = Phoenix.SessionProcess.start("user_123")
      :ok = Phoenix.SessionProcess.terminate("user_123")
      {:error, :not_found} = Phoenix.SessionProcess.terminate("user_123")
  """
  @spec terminate(binary()) :: :ok | {:error, :not_found}
  defdelegate terminate(session_id),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :terminate_session

  @doc """
  Refreshes the TTL for a session, extending its lifetime.

  Call this function when you want to keep a session alive beyond its
  normal TTL. This is useful for active sessions that should not expire
  even if they haven't received calls or casts recently.

  ## Parameters
  - `session_id` - Unique binary identifier for the session

  ## Returns
  - `:ok` - Session TTL refreshed successfully
  - `{:error, :not_found}` - Session does not exist

  ## Examples

      {:ok, _pid} = Phoenix.SessionProcess.start("user_123")

      # Keep session alive
      :ok = Phoenix.SessionProcess.touch("user_123")

      # Session TTL is reset to full duration
  """
  @spec touch(binary()) :: :ok | {:error, :not_found}
  def touch(session_id) do
    if started?(session_id) do
      Cleanup.refresh_session(session_id)
      :ok
    else
      {:error, :not_found}
    end
  end

  @doc """
  Makes a synchronous call to a session process.

  Sends a synchronous request to the session process and waits for a response.
  The request is handled by the session process's `handle_call/3` callback.

  ## Parameters
  - `session_id` - Unique binary identifier for the session
  - `request` - The request message to send
  - `timeout` - Maximum time to wait for response in milliseconds (default: 15,000)

  ## Returns
  - Response from the session process's `handle_call/3` callback
  - `{:error, {:session_not_found, id}}` - Session does not exist
  - `{:error, {:timeout, timeout}}` - Request timed out

  ## Examples

      {:ok, _pid} = Phoenix.SessionProcess.start("user_123")
      {:ok, state} = Phoenix.SessionProcess.call("user_123", :get_state)
      {:ok, :pong} = Phoenix.SessionProcess.call("user_123", :ping, 5_000)
  """
  @spec call(binary(), any(), :infinity | non_neg_integer()) :: any()
  defdelegate call(session_id, request, timeout \\ 15_000),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :call_on_session

  @doc """
  Sends an asynchronous message to a session process.

  Sends a fire-and-forget message to the session process. The message is handled
  by the session process's `handle_cast/2` callback. Does not wait for a response.

  ## Parameters
  - `session_id` - Unique binary identifier for the session
  - `request` - The message to send

  ## Returns
  - `:ok` - Message sent successfully
  - `{:error, {:session_not_found, id}}` - Session does not exist

  ## Examples

      {:ok, _pid} = Phoenix.SessionProcess.start("user_123")
      :ok = Phoenix.SessionProcess.cast("user_123", {:put, :user_id, 123})
      :ok = Phoenix.SessionProcess.cast("user_123", {:delete, :old_key})
  """
  @spec cast(binary(), any()) :: :ok | {:error, term()}
  defdelegate cast(session_id, request),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :cast_on_session

  @doc """
  Returns all active sessions as a list of `{session_id, pid}` tuples.

  ## Examples

      iex> is_list(Phoenix.SessionProcess.list_session())
      true

      # Returns list of {session_id, pid} tuples, or empty list if no sessions exist
  """
  @spec list_session :: [{binary(), pid()}]
  def list_session do
    Registry.select(SessionRegistry, [
      {{:"$1", :"$2", :_}, [{:is_binary, :"$1"}], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc """
  Returns session statistics including total count and modules in use.

  ## Examples

      iex> info = Phoenix.SessionProcess.session_info()
      iex> is_map(info)
      true
      iex> Map.has_key?(info, :count)
      true
      iex> Map.has_key?(info, :modules)
      true

  ## Returns

  - `%{count: integer(), modules: list(module())}` - A map containing the total number of active sessions and a list of unique session process modules.
  """
  @spec session_info :: %{count: integer(), modules: list(module())}
  def session_info do
    sessions = list_session()

    modules =
      sessions
      |> Enum.map(fn {_session_id, pid} ->
        case Registry.lookup(SessionRegistry, pid) do
          [{_, module}] -> module
          _ -> Config.session_process()
        end
      end)
      |> Enum.uniq()

    %{
      count: length(sessions),
      modules: modules
    }
  end

  @doc """
  Returns all session IDs for sessions managed by a specific module.

  ## Examples

      iex> sessions = Phoenix.SessionProcess.list_sessions_by_module(MyApp.SessionProcess)
      iex> is_list(sessions)
      true
      iex> Enum.all?(sessions, &is_binary/1)
      true

  ## Parameters

  - `module` - The session process module to filter by

  ## Returns

  - `[binary()]` - List of session IDs managed by the specified module
  """
  @spec list_sessions_by_module(module()) :: [binary()]
  def list_sessions_by_module(module) do
    list_session()
    |> Enum.filter(fn {_session_id, pid} ->
      case Registry.lookup(SessionRegistry, pid) do
        [{_, ^module}] -> true
        _ -> false
      end
    end)
    |> Enum.map(fn {session_id, _pid} -> session_id end)
  end

  @doc """
  Finds a session by its ID and returns its PID if it exists.

  This is different from `started?/1` in that it returns the actual PID
  of the session process, which can be used for direct process operations.

  ## Examples

      iex> {:ok, pid} = Phoenix.SessionProcess.find_session("existing_session_id")
      iex> is_pid(pid)
      true

      iex> {:error, :not_found} = Phoenix.SessionProcess.find_session("nonexistent_session_id")
      iex> {:error, :not_found}

  ## Parameters

  - `session_id` - The session ID to look up

  ## Returns

  - `{:ok, pid()}` - The PID of the session process if found
  - `{:error, :not_found}` - If the session doesn't exist
  """
  @spec find_session(binary()) :: {:ok, pid()} | {:error, :not_found}
  def find_session(session_id) do
    case ProcessSupervisor.session_process_pid(session_id) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  @doc """
  Returns detailed session statistics including process count and memory usage.

  Useful for monitoring and debugging session process performance.

  ## Examples

      iex> stats = Phoenix.SessionProcess.session_stats()
      iex> is_map(stats)
      true
      iex> Map.has_key?(stats, :total_sessions)
      true
      iex> Map.has_key?(stats, :memory_usage)
      true
      iex> Map.has_key?(stats, :avg_memory_per_session)
      true

  ## Returns

  - `%{total_sessions: integer(), memory_usage: integer(), avg_memory_per_session: integer()}` - Session statistics map
    - `total_sessions` - Total number of active session processes
    - `memory_usage` - Total memory usage in bytes for all session processes
    - `avg_memory_per_session` - Average memory usage per session in bytes
  """
  @spec session_stats :: %{
          total_sessions: integer(),
          memory_usage: integer(),
          avg_memory_per_session: integer()
        }
  def session_stats do
    sessions = list_session()
    total_sessions = length(sessions)
    memory_usage = calculate_total_memory(sessions)
    avg_memory = calculate_average_memory(memory_usage, total_sessions)

    %{
      total_sessions: total_sessions,
      memory_usage: memory_usage,
      avg_memory_per_session: avg_memory
    }
  end

  defp calculate_total_memory([]), do: 0

  defp calculate_total_memory(sessions) do
    sessions
    |> Enum.map(&get_process_memory/1)
    |> Enum.sum()
  end

  defp get_process_memory({_session_id, pid}) do
    case :erlang.process_info(pid, :memory) do
      {:memory, memory} -> memory
      _ -> 0
    end
  end

  defp calculate_average_memory(_memory, 0), do: 0
  defp calculate_average_memory(memory, total), do: div(memory, total)

  # ============================================================================
  # Redux Store API
  # ============================================================================

  @doc """
  Dispatch an action to a session process asynchronously (fire-and-forget).

  The action will be processed through all registered reducers and subscribers
  will be notified if their selected state changed. This function returns
  immediately without waiting for the action to be processed.

  ## Parameters
  - `session_id` - Session identifier
  - `action` - Action to dispatch (any term)
  - `opts` - Options keyword list:
    - `:payload` - Payload for the action
    - `:reducers` - List of reducer names to target
    - `:reducer_prefix` - Prefix to filter reducers by
    - `:async` - Ignored (always async)

  ## Returns
  - `:ok` - Action dispatched successfully
  - `{:error, {:session_not_found, session_id}}` - If session doesn't exist

  ## Examples

      # Simple action
      :ok = SessionProcess.dispatch(session_id, "user.reload")

      # Action with payload
      :ok = SessionProcess.dispatch(session_id, "user.update", payload: %{name: "Alice"})

      # Target specific reducers
      :ok = SessionProcess.dispatch(session_id, "reload", reducers: [:user, :cart])

      # Use prefix routing
      :ok = SessionProcess.dispatch(session_id, "fetch-data", reducer_prefix: "user")
  """
  @spec dispatch(binary(), any(), keyword()) :: :ok | {:error, term()}
  def dispatch(session_id, action, opts \\ []) do
    alias Phoenix.SessionProcess.Redux.Action

    # Normalize action with all opts (including routing metadata)
    normalized_action = Action.normalize(action, opts)

    case ProcessSupervisor.session_process_pid(session_id) do
      nil ->
        {:error, {:session_not_found, session_id}}

      _pid ->
        cast(session_id, {:dispatch_action, normalized_action})
        :ok
    end
  end

  @doc """
  Dispatch an action asynchronously with explicit function name.

  This is an alias for `dispatch/3` for better clarity when dispatching async actions.
  All dispatches are asynchronous by default.

  ## Parameters
  - `session_id` - Session identifier
  - `action` - Action to dispatch
  - `opts` - Options (see `dispatch/3`)

  ## Returns
  - `:ok` - Action dispatched successfully
  - `{:error, {:session_not_found, session_id}}` - If session doesn't exist

  ## Examples

      # Explicit async dispatch
      :ok = SessionProcess.dispatch_async(session_id, "user.reload")

      # With payload
      :ok = SessionProcess.dispatch_async(session_id, "update", payload: data)
  """
  @spec dispatch_async(binary(), any(), keyword()) :: :ok | {:error, term()}
  def dispatch_async(session_id, action, opts \\ []) do
    dispatch(session_id, action, opts)
  end

  @doc """
  Subscribe to state changes with a selector function.

  The selector will be called with the current state immediately, and you'll
  receive a message with the selected value. Then, on each state change, if the
  selected value changes, you'll receive another message.

  ## Parameters
  - `session_id` - Session identifier
  - `selector` - Function that extracts data from state: `(state) -> selected_data`
  - `event_name` - Atom for the message event (default: :state_changed)
  - `pid` - Process to receive notifications (default: self())

  ## Returns
  - `{:ok, subscription_id}` - Unique reference for this subscription
  - `{:error, reason}` - If session not found

  ## Messages
  Subscriber receives: `{event_name, selected_data}`

  ## Examples

      # Subscribe to user data
      {:ok, sub_id} = SessionProcess.subscribe(
        session_id,
        fn state -> state.user end,
        :user_changed
      )

      # Immediately receive current user
      receive do
        {:user_changed, user} -> IO.puts("Current user: \#{inspect(user)}")
      end

      # Receive updates when user changes
      receive do
        {:user_changed, new_user} -> IO.puts("User updated: \#{inspect(new_user)}")
      end

      # Later, unsubscribe
      SessionProcess.unsubscribe(session_id, sub_id)
  """
  @spec subscribe(binary(), function(), atom(), pid()) :: {:ok, reference()} | {:error, term()}
  def subscribe(session_id, selector, event_name \\ :state_changed, pid \\ self())
      when is_function(selector, 1) and is_atom(event_name) and is_pid(pid) do
    call(session_id, {:subscribe_with_selector, selector, event_name, pid})
  end

  @doc """
  Unsubscribe from state changes.

  ## Parameters
  - `session_id` - Session identifier
  - `subscription_id` - Reference returned from `subscribe/4`

  ## Returns
  - `:ok` - Successfully unsubscribed
  - `{:error, reason}` - If session not found

  ## Examples

      {:ok, sub_id} = SessionProcess.subscribe(session_id, selector, :event)
      # ... later ...
      :ok = SessionProcess.unsubscribe(session_id, sub_id)
  """
  @spec unsubscribe(binary(), reference()) :: :ok | {:error, term()}
  def unsubscribe(session_id, subscription_id) when is_reference(subscription_id) do
    call(session_id, {:unsubscribe, subscription_id})
  end

  @doc """
  Register a reducer function for the session.

  Reducers are called in registration order when actions are dispatched.

  ## Parameters
  - `session_id` - Session identifier
  - `name` - Atom identifier for this reducer
  - `reducer_fn` - Function with signature: `(action, state) -> new_state`

  ## Returns
  - `:ok` - Reducer registered successfully
  - `{:error, reason}` - If session not found

  ## Examples

      defmodule MyReducers do
        def counter_reducer(action, state) do
          case action do
            :increment -> %{state | count: state.count + 1}
            :decrement -> %{state | count: state.count - 1}
            {:set, value} -> %{state | count: value}
            _ -> state
          end
        end
      end

      SessionProcess.register_reducer(
        session_id,
        :counter,
        &MyReducers.counter_reducer/2
      )
  """
  @spec register_reducer(binary(), atom(), function()) :: :ok | {:error, term()}
  def register_reducer(session_id, name, reducer_fn)
      when is_atom(name) and is_function(reducer_fn, 2) do
    call(session_id, {:register_reducer, name, reducer_fn})
  end

  @doc """
  Register a named selector for the session.

  Named selectors can be retrieved and reused by name.

  ## Parameters
  - `session_id` - Session identifier
  - `name` - Atom identifier for this selector
  - `selector_fn` - Function with signature: `(state) -> selected_data`

  ## Returns
  - `:ok` - Selector registered successfully
  - `{:error, reason}` - If session not found

  ## Examples

      SessionProcess.register_selector(
        session_id,
        :user_name,
        fn state -> get_in(state, [:user, :name]) end
      )

      # Later, use the selector
      name = SessionProcess.select(session_id, :user_name)
  """
  @spec register_selector(binary(), atom(), function()) :: :ok | {:error, term()}
  def register_selector(session_id, name, selector_fn)
      when is_atom(name) and is_function(selector_fn, 1) do
    call(session_id, {:register_selector, name, selector_fn})
  end

  @doc """
  Get the current state, optionally applying a selector.

  ## Parameters
  - `session_id` - Session identifier
  - `selector` - Optional selector function or registered selector name

  ## Returns
  - State or selected data
  - `{:error, reason}` - If session not found

  ## Examples

      # Get full state
      state = SessionProcess.get_state(session_id)

      # Get with inline selector
      user = SessionProcess.get_state(session_id, fn s -> s.user end)

      # Get with registered selector
      user = SessionProcess.get_state(session_id, :current_user)
  """
  @spec get_state(binary(), function() | atom() | nil) :: any()
  def get_state(session_id, selector \\ nil) do
    case call(session_id, :get_state) do
      {:ok, state} when is_nil(selector) ->
        state

      {:ok, state} when is_function(selector, 1) ->
        selector.(state)

      {:ok, state} when is_atom(selector) ->
        # Get registered selector and apply it
        case call(session_id, {:get_selector, selector}) do
          {:ok, selector_fn} -> selector_fn.(state)
          _ -> state
        end

      error ->
        error
    end
  end

  @doc """
  Apply a registered selector by name.

  ## Parameters
  - `session_id` - Session identifier
  - `selector_name` - Atom name of registered selector

  ## Returns
  - Selected data
  - `{:error, reason}` - If session or selector not found

  ## Examples

      SessionProcess.register_selector(session_id, :count, fn s -> s.count end)
      count = SessionProcess.select(session_id, :count)
  """
  @spec select(binary(), atom()) :: any()
  def select(session_id, selector_name) when is_atom(selector_name) do
    case call(session_id, {:get_selector, selector_name}) do
      {:ok, selector_fn} ->
        case call(session_id, :get_state) do
          {:ok, state} -> selector_fn.(state)
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Defines a reducer module for managing state slices.

  ## Usage

      defmodule MyApp.Reducers.UserReducer do
        use Phoenix.SessionProcess, :reducer

        def init_state do
          %{users: [], loading: false, query: nil}
        end

        @throttle {"fetch-list", "3000ms"}
        def handle_action(%{type: "fetch-list"}, state) do
          # Throttled: Only executes once per 3 seconds
          %{state | loading: true}
        end

        @debounce {"update-query", "500ms"}
        def handle_action(%{type: "update-query", payload: query}, state) do
          # Debounced: Waits 500ms after last call
          %{state | query: query}
        end

        def handle_async(%{type: "load", payload: %{page: page}}, dispatch, state) do
          # Async action with dispatch callback
          Task.async(fn ->
            data = fetch_data(page)
            dispatch.(%{type: "load_success", payload: data})
          end)
          %{state | loading: true}
        end
      end

  ## Callbacks

  - `init_state/0` - Define initial state for this reducer's slice (optional, defaults to `%{}`)
  - `handle_action/2` - Handle synchronous actions, return updated state
  - `handle_async/3` - Handle async actions with dispatch callback, return updated state

  ## Module Attributes

  - `@throttle {action_pattern, duration}` - Throttle action (execute immediately, then block)
  - `@debounce {action_pattern, duration}` - Debounce action (delay execution, reset timer)

  Duration format: `"500ms"`, `"1s"`, `"5m"`, `"1h"`

  ## State Initialization

  Each reducer defines its initial state via `init_state/0`. When using `combined_reducers/0`,
  the SessionProcess automatically calls each reducer's `init_state/0` to build the complete
  initial state with each reducer's slice.
  """
  defmacro __using__(:reducer) do
    quote do
      @before_compile Phoenix.SessionProcess.Redux.ReducerCompiler

      # Reducer identity
      Module.register_attribute(__MODULE__, :name, accumulate: false)
      Module.register_attribute(__MODULE__, :action_prefix, accumulate: false)

      # Accumulators for all throttle/debounce configs
      Module.register_attribute(__MODULE__, :action_throttles, accumulate: true)
      Module.register_attribute(__MODULE__, :action_debounces, accumulate: true)

      # Single-value attributes that get reset after each function definition
      Module.register_attribute(__MODULE__, :throttle, accumulate: false)
      Module.register_attribute(__MODULE__, :debounce, accumulate: false)

      # Hook to capture attributes when functions are defined
      @on_definition {Phoenix.SessionProcess, :__on_reducer_definition__}

      @doc """
      Initialize the reducer's state slice.

      Override this function to provide the initial state for this reducer's slice.

      ## Returns

      - `initial_state` - The initial state map for this reducer

      ## Examples

          def init_state do
            %{users: [], loading: false, query: nil}
          end

          def init_state do
            %{items: [], total: 0}
          end
      """
      def init_state, do: %{}

      @doc """
      Handle synchronous actions.

      Override this function to process actions and return updated state.

      ## Parameters

      - `action` - The action to process (any term)
      - `state` - The current state slice for this reducer

      ## Returns

      - `new_state` - The updated state slice

      ## Examples

          def handle_action(:increment, state) do
            %{state | count: state.count + 1}
          end

          def handle_action(%{type: "set_user", payload: user}, state) do
            %{state | current_user: user}
          end
      """
      def handle_action(_action, state), do: state

      @doc """
      Handle asynchronous actions with dispatch callback.

      Override this function for actions that require async operations.
      The dispatch callback allows you to dispatch new actions from async context.

      ## Parameters

      - `action` - The action to process
      - `dispatch` - Callback function to dispatch new actions: `dispatch.(action)`
      - `state` - The current state slice for this reducer

      ## Returns

      - `new_state` - The updated state slice

      ## Examples

          def handle_async(%{type: "fetch_user", payload: id}, dispatch, state) do
            Task.async(fn ->
              user = API.fetch_user(id)
              dispatch.(%{type: "fetch_user_success", payload: user})
            rescue
              error ->
                dispatch.(%{type: "fetch_user_error", payload: %{error: error}})
            end)

            %{state | loading: true}
          end
      """
      def handle_async(_action, _dispatch, state), do: state

      defoverridable init_state: 0, handle_action: 2, handle_async: 3
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
  defmacro __using__(:process) do
    quote do
      use GenServer

      # ========================================================================
      # GenServer Boilerplate
      # ========================================================================

      def start_link(opts) do
        arg = Keyword.get(opts, :arg, %{})
        name = Keyword.get(opts, :name)
        GenServer.start_link(__MODULE__, arg, name: name)
      end

      def get_session_id do
        current_pid = self()

        case Registry.select(unquote(SessionRegistry), [
               {{:"$1", :"$2", :_}, [{:==, :"$2", current_pid}], [{{:"$1", :"$2"}}]}
             ])
             |> Enum.at(0) do
          {session_id, _pid} ->
            session_id

          nil ->
            raise "Session process not yet registered or registration failed"
        end
      end

      # ========================================================================
      # Redux Infrastructure - Default Implementation
      # ========================================================================

      @doc """
      Initialize session process state with Redux infrastructure.

      Override `init_state/1` to provide your application's initial state.
      """
      @impl true
      def init(arg) do
        # Call user's initialization - init_state/1 delegates to user_init/1 by default
        user_state = init_state(arg)

        # Load combined reducers if defined
        combined =
          if function_exported?(__MODULE__, :combined_reducers, 0) do
            combined_reducers()
          else
            []
          end

        # Build reducer map from combined_reducers (validates entries)
        redux_reducers = build_combined_reducers(combined)

        # Initialize state slices from each reducer's init_state
        # Use the validated redux_reducers map
        app_state =
          Enum.reduce(redux_reducers, user_state, fn {slice_key,
                                                      {:combined, module, _name, _prefix}},
                                                     acc ->
            init_reducer_slice(slice_key, module, acc)
          end)

        # Wrap in Redux infrastructure
        state = %{
          # User's application state (with initialized reducer slices)
          app_state: app_state,

          # Redux infrastructure (internal, prefixed with _redux_)
          _redux_reducers: redux_reducers,
          _redux_reducer_slices: Map.keys(redux_reducers),
          _redux_selectors: %{},
          _redux_subscriptions: [],
          _redux_middleware: [],
          _redux_history: [],
          _redux_max_history: 100,
          # NEW: Throttle/debounce state
          _redux_throttle_state: %{},
          _redux_debounce_timers: %{}
        }

        {:ok, state}
      end

      @doc """
      Initialize your application's state.

      Override this callback to provide your initial state as a map.
      This replaces the deprecated `user_init/1` callback.

      For backward compatibility, init_state/1 delegates to user_init/1 by default.
      You can override either callback - init_state/1 is preferred for new code.

      ## Examples

          def init_state(_arg) do
            %{count: 0, user: nil, items: []}
          end

          def init_state(user_id) do
            %{user_id: user_id, cart: [], preferences: %{}}
          end
      """
      def init_state(arg), do: user_init(arg)

      @doc """
      Define combined reducers for state slicing.

      Override this callback to return a list of reducer modules or tuples.
      Each reducer module manages its own portion of the state.

      ## Examples

          def combined_reducers() do
            [
              MyApp.Reducers.UserReducer,           # Uses module's @name and @action_prefix
              {:cart, MyApp.Reducers.CartReducer},  # Custom name, action_prefix = "cart"
              {:shipping, MyApp.Reducers.ShippingReducer, "ship"}  # Custom name and action_prefix
            ]
          end

      ## List Formats

      The list can contain three formats:

      1. **Module atom** - Uses the reducer's `@name` and `@action_prefix` attributes:
         - `UserReducer` → name from `@name`, action_prefix from `@action_prefix` (defaults to stringified `@name`)

      2. **{name, Module} tuple** - Custom name, action_prefix defaults to stringified name:
         - `{:cart, CartReducer}` → name = `:cart`, action_prefix = `"cart"`

      3. **{name, Module, action_prefix} tuple** - Explicit name and action_prefix:
         - `{:shipping, ShippingReducer, "ship"}` → name = `:shipping`, action_prefix = `"ship"`

      ## State Slicing

      Each reducer receives only its slice of state based on the name:

      - UserReducer receives `state.users` (if @name is :users)
      - CartReducer receives `state.cart` (from {:cart, CartReducer})
      - ShippingReducer receives `state.shipping` (from {:shipping, ...})

      ## Action Routing

      Actions are routed to reducers based on their `@action_prefix` attribute:

      - `"user.reload"` → Routes to reducer with action_prefix `"user"`
      - `"cart.add"` → Routes to reducer with action_prefix `"cart"`
      - `"ship.calculate"` → Routes to reducer with action_prefix `"ship"`

      You can also explicitly target reducers in dispatch:

          dispatch(session_id, "reload", reducers: [:user, :cart])
      """
      def combined_reducers, do: []

      @doc deprecated: "Use init_state/1 instead"
      @doc """
      User-defined initialization (DEPRECATED).

      Return your application's initial state as a map.

      **DEPRECATED**: This callback is deprecated as of v0.7.0.
      Please use `init_state/1` instead for better clarity.

      ## Examples

          def user_init(_arg) do
            %{count: 0, user: nil, items: []}
          end
      """
      def user_init(_arg), do: %{}

      # ========================================================================
      # Redux Dispatch Handlers
      # ========================================================================

      @impl true
      def handle_call({:dispatch_action, action}, _from, state) do
        new_state = dispatch_with_reducers(action, state)

        # Add action to history
        new_state_with_history = %{
          new_state
          | _redux_history:
              add_to_history(action, new_state._redux_history, new_state._redux_max_history)
        }

        {:reply, {:ok, new_state_with_history.app_state}, new_state_with_history}
      end

      @impl true
      def handle_cast({:dispatch_action, action}, state) do
        new_state = dispatch_with_reducers(action, state)
        {:noreply, new_state}
      end

      # ========================================================================
      # Subscription Handlers
      # ========================================================================

      @impl true
      def handle_call({:subscribe_with_selector, selector, event_name, pid}, _from, state) do
        # Generate unique subscription ID
        sub_id = make_ref()

        # Monitor subscriber
        monitor_ref = Process.monitor(pid)

        # Get initial value
        initial_value = selector.(state.app_state)

        # Send immediately
        send(pid, {event_name, initial_value})

        # Create subscription
        subscription = %{
          id: sub_id,
          pid: pid,
          selector: selector,
          event_name: event_name,
          last_value: initial_value,
          monitor_ref: monitor_ref
        }

        new_state = %{
          state
          | _redux_subscriptions: [subscription | state._redux_subscriptions]
        }

        {:reply, {:ok, sub_id}, new_state}
      end

      @impl true
      def handle_call({:unsubscribe, sub_id}, _from, state) do
        case Enum.find(state._redux_subscriptions, &(&1.id == sub_id)) do
          nil ->
            {:reply, :ok, state}

          subscription ->
            Process.demonitor(subscription.monitor_ref, [:flush])
            new_subs = Enum.reject(state._redux_subscriptions, &(&1.id == sub_id))
            {:reply, :ok, %{state | _redux_subscriptions: new_subs}}
        end
      end

      # ========================================================================
      # Reducer/Selector Management
      # ========================================================================

      @impl true
      def handle_call({:register_reducer, name, reducer_fn}, _from, state) do
        new_reducers = Map.put(state._redux_reducers, name, reducer_fn)
        {:reply, :ok, %{state | _redux_reducers: new_reducers}}
      end

      @impl true
      def handle_call({:register_selector, name, selector_fn}, _from, state) do
        new_selectors = Map.put(state._redux_selectors, name, selector_fn)
        {:reply, :ok, %{state | _redux_selectors: new_selectors}}
      end

      @impl true
      def handle_call({:get_selector, name}, _from, state) do
        case Map.fetch(state._redux_selectors, name) do
          {:ok, selector_fn} -> {:reply, {:ok, selector_fn}, state}
          :error -> {:reply, {:error, {:selector_not_found, name}}, state}
        end
      end

      @impl true
      def handle_call(:get_state, _from, state) do
        {:reply, {:ok, state.app_state}, state}
      end

      # ========================================================================
      # Process Monitoring
      # ========================================================================

      @impl true
      def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
        new_subs = Enum.reject(state._redux_subscriptions, &(&1.monitor_ref == ref))
        {:noreply, %{state | _redux_subscriptions: new_subs}}
      end

      @impl true
      def handle_info({:debounced_action, module, action}, state) do
        # Process the debounced action - find the slice_key for this module
        slice_key =
          Enum.find_value(state._redux_reducers, fn
            {key, {:combined, ^module, _, _}} -> key
            _ -> nil
          end)

        if slice_key do
          # Apply the reducer
          slice_state = Map.get(state.app_state, slice_key, %{})
          new_slice_state = module.handle_action(action, slice_state)
          new_app_state = Map.put(state.app_state, slice_key, new_slice_state)

          # Notify subscriptions if changed
          new_subscriptions =
            if new_app_state != state.app_state do
              notify_all_subscriptions(new_app_state, state._redux_subscriptions)
            else
              state._redux_subscriptions
            end

          new_state = %{
            state
            | app_state: new_app_state,
              _redux_subscriptions: new_subscriptions
          }

          {:noreply, new_state}
        else
          {:noreply, state}
        end
      end

      # ========================================================================
      # Private Helpers
      # ========================================================================

      defp build_combined_reducers(combined) when is_list(combined) do
        Enum.reduce(combined, %{}, fn
          # Format 1: Module - use module's @name and @action_prefix
          module, acc when is_atom(module) ->
            validate_reducer_module!(module)
            name = module.__reducer_name__()
            action_prefix = module.__reducer_action_prefix__()

            if Map.has_key?(acc, name) do
              raise ArgumentError, """
              Duplicate reducer name: #{inspect(name)}

              Reducer names must be unique in combined_reducers/0.
              Found duplicate for name #{inspect(name)}.

              Check your combined_reducers/0 list and ensure each reducer has a unique @name.
              """
            end

            Map.put(acc, name, {:combined, module, name, action_prefix})

          # Format 2: {name, Module} - use name, action_prefix = stringified name
          {name, module}, acc when is_atom(name) and is_atom(module) ->
            validate_reducer_module!(module)
            action_prefix = to_string(name)

            if Map.has_key?(acc, name) do
              raise ArgumentError, """
              Duplicate reducer name: #{inspect(name)}

              Reducer names must be unique in combined_reducers/0.
              Found duplicate for name #{inspect(name)}.

              Check your combined_reducers/0 list and ensure each name is unique.
              """
            end

            Map.put(acc, name, {:combined, module, name, action_prefix})

          # Format 3: {name, Module, action_prefix} - explicit name and action_prefix
          {name, module, action_prefix}, acc
          when is_atom(name) and is_atom(module) and
                 (is_binary(action_prefix) or is_nil(action_prefix)) ->
            validate_reducer_module!(module)

            if Map.has_key?(acc, name) do
              raise ArgumentError, """
              Duplicate reducer name: #{inspect(name)}

              Reducer names must be unique in combined_reducers/0.
              Found duplicate for name #{inspect(name)}.

              Check your combined_reducers/0 list and ensure each name is unique.
              """
            end

            Map.put(acc, name, {:combined, module, name, action_prefix})

          # Invalid format - catch-all with helpful error
          invalid, _acc ->
            raise ArgumentError, """
            Invalid combined_reducers entry: #{inspect(invalid)}

            Expected one of:
              - Module (atom) - uses module's @name and @action_prefix
              - {name, Module} (2-tuple) - custom name, action_prefix defaults to name
              - {name, Module, action_prefix} (3-tuple) - custom name and action_prefix (can be nil)

            Example:
                def combined_reducers do
                  [
                    UserReducer,                     # Uses @name and @action_prefix from module
                    {:cart, CartReducer},            # Name: :cart, action_prefix: "cart"
                    {:shipping, ShipReducer, "ship"}, # Name: :shipping, action_prefix: "ship"
                    {:global, GlobalReducer, nil}    # Name: :global, no action_prefix (handles all)
                  ]
                end

            Got: #{inspect(invalid)}
            """
        end)
      end

      # Handle old map format for backward compatibility
      defp build_combined_reducers(combined) when is_map(combined) do
        Enum.into(combined, %{}, fn {slice_key, module} ->
          # For maps, use slice_key as both name and action_prefix
          action_prefix = to_string(slice_key)
          {slice_key, {:combined, module, slice_key, action_prefix}}
        end)
      end

      defp validate_reducer_module!(module) do
        case Code.ensure_loaded(module) do
          {:module, _} ->
            :ok

          {:error, _reason} ->
            raise ArgumentError, """
            Could not load reducer module: #{inspect(module)}

            Make sure the module is compiled and available.
            """
        end

        unless function_exported?(module, :__reducer_name__, 0) do
          raise ArgumentError, """
          Module #{inspect(module)} is not a reducer module.

          Reducer modules must use the :reducer macro and define @name.

          Did you forget to add:
              use Phoenix.SessionProcess, :reducer
              @name :reducer_name

          Example:
              defmodule MyReducer do
                use Phoenix.SessionProcess, :reducer

                @name :my_reducer
                @action_prefix "my"  # Optional, defaults to @name (can be nil or "" for catch-all)

                def init_state, do: %{}

                def handle_action(action, state) do
                  # ...
                end
              end
          """
        end
      end

      defp init_reducer_slice(slice_key, module, state) do
        slice_initial_state =
          if function_exported?(module, :init_state, 0) do
            module.init_state()
          else
            %{}
          end

        Map.put(state, slice_key, slice_initial_state)
      end

      defp apply_combined_reducer(module, action, slice_key, app_state, internal_state) do
        alias Phoenix.SessionProcess.Redux.ActionRateLimiter

        # Get the state slice for this reducer
        slice_state = Map.get(app_state, slice_key, %{})

        # Check throttle first
        if ActionRateLimiter.should_throttle?(module, action, internal_state) do
          # Skip action due to throttle
          {app_state, internal_state}
        else
          # Check debounce
          if ActionRateLimiter.should_debounce?(module, action) do
            # Schedule debounced action
            new_internal_state =
              ActionRateLimiter.schedule_debounce(module, action, self(), internal_state)

            # Return unchanged app_state but updated internal_state
            {app_state, new_internal_state}
          else
            # Execute action
            new_slice_state =
              if function_exported?(module, :handle_async, 3) and async_action?(action) do
                # Async action - provide dispatch callback
                dispatch_fn = fn new_action ->
                  GenServer.cast(self(), {:dispatch_action, new_action})
                end

                module.handle_async(action, dispatch_fn, slice_state)
              else
                # Synchronous action
                module.handle_action(action, slice_state)
              end

            # Update app_state with new slice
            new_app_state = Map.put(app_state, slice_key, new_slice_state)

            # Record throttle if needed
            new_internal_state = ActionRateLimiter.record_throttle(module, action, internal_state)

            {new_app_state, new_internal_state}
          end
        end
      end

      defp async_action?(%Phoenix.SessionProcess.Redux.Action{} = action) do
        # Check if action has async metadata flag
        Phoenix.SessionProcess.Redux.Action.async?(action)
      end

      defp async_action?(%{type: type}) when is_binary(type),
        do: String.ends_with?(type, "_async")

      defp async_action?(_), do: false

      defp dispatch_with_reducers(action, state) do
        alias Phoenix.SessionProcess.Redux.Action

        # Normalize action to Action struct for consistent routing and pattern matching
        normalized_action = Action.normalize(action, [])

        old_app_state = state.app_state

        # Determine which reducers should handle this action based on routing metadata
        reducers_to_apply = filter_reducers_for_action(normalized_action, state._redux_reducers)

        # Apply filtered reducers
        {new_app_state, new_internal_state} =
          Enum.reduce(reducers_to_apply, {old_app_state, state}, fn
            # Combined reducer (from combined_reducers/0) - new format with prefix
            {_name, {:combined, module, slice_key, _prefix}}, {acc_app_state, acc_internal_state} ->
              {updated_app_state, updated_internal_state} =
                apply_combined_reducer(
                  module,
                  normalized_action,
                  slice_key,
                  acc_app_state,
                  acc_internal_state
                )

              {updated_app_state, updated_internal_state}

            # Manual reducer (from register_reducer/3)
            {_name, reducer_fn}, {acc_app_state, acc_internal_state} when is_function(reducer_fn) ->
              new_acc_app_state = reducer_fn.(normalized_action, acc_app_state)
              {new_acc_app_state, acc_internal_state}
          end)

        # Notify subscribers if state changed
        new_subscriptions =
          if new_app_state != old_app_state do
            notify_all_subscriptions(new_app_state, new_internal_state._redux_subscriptions)
          else
            new_internal_state._redux_subscriptions
          end

        # Return updated internal state with new app_state and subscriptions
        updated_internal_state = %{
          new_internal_state
          | app_state: new_app_state,
            _redux_subscriptions: new_subscriptions
        }

        updated_internal_state
      end

      # Filter reducers based on action routing metadata
      defp filter_reducers_for_action(action, all_reducers) do
        alias Phoenix.SessionProcess.Redux.Action

        # Check explicit reducer targeting (highest priority)
        case Action.target_reducers(action) do
          nil ->
            # No explicit targets, check for prefix routing
            filter_by_prefix(action, all_reducers)

          target_list when is_list(target_list) ->
            # Explicit list of reducer names to target
            Enum.filter(all_reducers, fn {name, _} -> name in target_list end)
        end
      end

      # Filter reducers by prefix (explicit or inferred from action type)
      defp filter_by_prefix(action, all_reducers) do
        alias Phoenix.SessionProcess.Redux.Action

        # Check for explicit prefix filter in action metadata
        prefix_filter = Action.reducer_prefix(action)

        # Infer prefix from action type if it's a string with dot notation
        inferred_prefix = infer_prefix_from_action(action)

        # Use explicit prefix filter, or inferred prefix, or nil (all reducers)
        prefix_to_match = prefix_filter || inferred_prefix

        case prefix_to_match do
          nil ->
            # No prefix routing, use all reducers
            all_reducers

          prefix when is_binary(prefix) and prefix != "" ->
            # Filter reducers with matching action_prefix or nil/empty action_prefix (catch-all)
            Enum.filter(all_reducers, fn
              {_name, {:combined, _module, _slice_key, reducer_action_prefix}} ->
                # Match if action_prefix matches, or if reducer has no action_prefix (nil or "")
                reducer_action_prefix == prefix or reducer_action_prefix == nil or
                  reducer_action_prefix == ""

              {_name, _reducer_fn} ->
                # Manual reducers have no action_prefix, always included
                true
            end)
        end
      end

      # Infer prefix from action type (e.g., "user.reload" -> "user")
      defp infer_prefix_from_action(%Phoenix.SessionProcess.Redux.Action{type: type})
           when is_binary(type) do
        case String.split(type, ".", parts: 2) do
          [prefix, _action] -> prefix
          [_] -> nil
        end
      end

      defp infer_prefix_from_action(_), do: nil

      defp notify_all_subscriptions(new_state, subscriptions) do
        Enum.map(subscriptions, fn sub ->
          new_value = sub.selector.(new_state)

          if new_value != sub.last_value do
            send(sub.pid, {sub.event_name, new_value})
            %{sub | last_value: new_value}
          else
            sub
          end
        end)
      end

      defp add_to_history(action, history, max_size) do
        entry = %{action: action, timestamp: DateTime.utc_now()}
        [entry | history] |> Enum.take(max_size)
      end

      # ========================================================================
      # Overridable Callbacks
      # ========================================================================

      defoverridable init: 1,
                     init_state: 1,
                     combined_reducers: 0,
                     user_init: 1,
                     handle_call: 3,
                     handle_cast: 2,
                     handle_info: 2
    end
  end

  defmacro __using__(:process_link) do
    quote do
      IO.warn(
        """
        :process_link is deprecated. Please use :process instead.

        All session processes now include LiveView monitoring functionality by default.
        LiveView integration now uses subscriptions to process state, so the explicit
        :process_link option is no longer necessary.

        Change:
          use Phoenix.SessionProcess, :process_link
        To:
          use Phoenix.SessionProcess, :process
        """,
        Macro.Env.stacktrace(__ENV__)
      )

      use Phoenix.SessionProcess, :process
    end
  end

  @doc false
  def __on_reducer_definition__(env, _kind, _name, _args, _guards, _body) do
    module = env.module

    # Check for @throttle attribute
    if throttle = Module.get_attribute(module, :throttle) do
      Phoenix.SessionProcess.Redux.ReducerCompiler.register_throttle(module, throttle)
      Module.delete_attribute(module, :throttle)
    end

    # Check for @debounce attribute
    if debounce = Module.get_attribute(module, :debounce) do
      Phoenix.SessionProcess.Redux.ReducerCompiler.register_debounce(module, debounce)
      Module.delete_attribute(module, :debounce)
    end
  end
end
