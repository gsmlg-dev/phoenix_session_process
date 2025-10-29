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
  Dispatch an action to a session process.

  The action will be processed through all registered reducers and subscribers
  will be notified if their selected state changed.

  ## Parameters
  - `session_id` - Session identifier
  - `action` - Action to dispatch (any term)
  - `opts` - Options keyword list:
    - `:async` - If true, dispatch asynchronously (default: false)
    - `:timeout` - Call timeout in ms (default: 5000)

  ## Returns
  - `{:ok, new_state}` - Synchronous dispatch returns new state
  - `:ok` - Asynchronous dispatch returns immediately
  - `{:error, reason}` - If session not found or dispatch fails

  ## Examples

      # Synchronous dispatch
      {:ok, new_state} = SessionProcess.dispatch(session_id, {:increment, 1})

      # Asynchronous dispatch
      :ok = SessionProcess.dispatch(session_id, {:increment, 1}, async: true)

      # With timeout
      {:ok, new_state} = SessionProcess.dispatch(session_id, action, timeout: 10_000)
  """
  @spec dispatch(binary(), any(), keyword()) :: {:ok, map()} | :ok | {:error, term()}
  def dispatch(session_id, action, opts \\ []) do
    async = Keyword.get(opts, :async, false)
    timeout = Keyword.get(opts, :timeout, 5000)

    if async do
      case ProcessSupervisor.session_process_pid(session_id) do
        nil ->
          {:error, {:session_not_found, session_id}}

        _pid ->
          cast(session_id, {:dispatch_action, action})
          :ok
      end
    else
      call(session_id, {:dispatch_action, action}, timeout)
    end
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

      Override `user_init/1` to provide your application's initial state.
      """
      @impl true
      def init(arg) do
        # Call user's initialization
        user_state = user_init(arg)

        # Wrap in Redux infrastructure
        state = %{
          # User's application state
          app_state: user_state,

          # Redux infrastructure (internal, prefixed with _redux_)
          _redux_reducers: %{},
          _redux_selectors: %{},
          _redux_subscriptions: [],
          _redux_middleware: [],
          _redux_history: [],
          _redux_max_history: 100
        }

        {:ok, state}
      end

      @doc """
      User-defined initialization.

      Return your application's initial state as a map.

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
        {new_app_state, new_subscriptions} = dispatch_with_reducers(action, state)

        new_state = %{
          state
          | app_state: new_app_state,
            _redux_subscriptions: new_subscriptions,
            _redux_history: add_to_history(action, state._redux_history, state._redux_max_history)
        }

        {:reply, {:ok, new_app_state}, new_state}
      end

      @impl true
      def handle_cast({:dispatch_action, action}, state) do
        {new_app_state, new_subscriptions} = dispatch_with_reducers(action, state)

        new_state = %{
          state
          | app_state: new_app_state,
            _redux_subscriptions: new_subscriptions
        }

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

      # ========================================================================
      # Private Helpers
      # ========================================================================

      defp dispatch_with_reducers(action, state) do
        old_app_state = state.app_state

        # Apply all registered reducers
        new_app_state =
          Enum.reduce(state._redux_reducers, old_app_state, fn {_name, reducer_fn}, acc_state ->
            reducer_fn.(action, acc_state)
          end)

        # Notify subscribers if state changed
        new_subscriptions =
          if new_app_state != old_app_state do
            notify_all_subscriptions(new_app_state, state._redux_subscriptions)
          else
            state._redux_subscriptions
          end

        {new_app_state, new_subscriptions}
      end

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
end
