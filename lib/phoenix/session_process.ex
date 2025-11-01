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
          {Phoenix.SessionProcess, []}
          # Or use: {Phoenix.SessionProcess.Supervisor, []}
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
          {:ok, _pid} = Phoenix.SessionProcess.start_session(session_id)

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
  Starts the SessionProcess supervision tree.

  This function delegates to `Phoenix.SessionProcess.Supervisor.start_link/1` and
  should be used in your application's supervision tree for cleaner syntax.

  ## Parameters
  - `init_arg` - Initialization argument (typically an empty list `[]`)

  ## Returns
  - `{:ok, pid}` - Supervisor started successfully
  - `{:error, reason}` - If supervisor failed to start

  ## Examples

  In your application supervision tree:

      def start(_type, _args) do
        children = [
          # Cleaner syntax using Phoenix.SessionProcess
          {Phoenix.SessionProcess, []}

          # Or explicitly use the Supervisor module
          {Phoenix.SessionProcess.Supervisor, []}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end
  """
  @spec start_link(any()) :: Supervisor.on_start()
  defdelegate start_link(init_arg), to: Phoenix.SessionProcess.Supervisor

  @doc """
  Returns a child specification for starting the SessionProcess supervision tree.

  This is automatically called when adding `{Phoenix.SessionProcess, []}` to a
  supervision tree. The function delegates to `Phoenix.SessionProcess.Supervisor.child_spec/1`.

  ## Parameters
  - `init_arg` - Initialization argument passed to `start_link/1`

  ## Returns
  - Child specification map with `:id`, `:start`, and other supervisor options

  ## Examples

  The child spec is automatically used in supervision trees:

      children = [
        {Phoenix.SessionProcess, []}  # child_spec/1 is called automatically
      ]
  """
  @spec child_spec(any()) :: Supervisor.child_spec()
  defdelegate child_spec(init_arg), to: Phoenix.SessionProcess.Supervisor

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

      {:ok, pid} = Phoenix.SessionProcess.start_session("user_123")
      {:error, {:already_started, pid}} = Phoenix.SessionProcess.start_session("user_123")
  """
  @spec start_session(binary()) :: {:ok, pid()} | {:error, term()}
  defdelegate start_session(session_id), to: Phoenix.SessionProcess.ProcessSupervisor

  @doc """
  Starts a session process with options.

  This allows you to customize the module and initialization arguments.

  ## Parameters
  - `session_id` - Unique binary identifier for the session
  - `opts` - Keyword list of options:
    - `:module` - Module implementing the session process behavior (defaults to configured module)
    - `:args` - Initialization arguments passed to `init/1` (defaults to nil)

  ## Returns
  - `{:ok, pid}` - Session process started successfully
  - `{:error, {:already_started, pid}}` - Session already exists
  - `{:error, {:invalid_session_id, id}}` - Invalid session ID format
  - `{:error, {:session_limit_reached, max}}` - Maximum sessions exceeded

  ## Examples

      # Use default module
      {:ok, pid} = Phoenix.SessionProcess.start_session("user_123")

      # Use custom module
      {:ok, pid} = Phoenix.SessionProcess.start_session("user_123", module: MyApp.CustomSessionProcess)

      # Use custom module with initialization arguments
      {:ok, pid} = Phoenix.SessionProcess.start_session("user_123",
        module: MyApp.SessionProcess,
        args: %{user_id: 123})

      # Use default module with initialization arguments
      {:ok, pid} = Phoenix.SessionProcess.start_session("user_456", args: [debug: true])

      iex> result = Phoenix.SessionProcess.start_session("valid_session", module: Phoenix.SessionProcess.DefaultSessionProcess)
      iex> match?({:ok, _pid}, result) or match?({:error, {:already_started, _pid}}, result)
      true

      iex> result = Phoenix.SessionProcess.start_session("valid_with_args", module: Phoenix.SessionProcess.DefaultSessionProcess, args: %{user_id: 123})
      iex> match?({:ok, _pid}, result) or match?({:error, {:already_started, _pid}}, result)
      true
  """
  @spec start_session(binary(), keyword()) :: {:ok, pid()} | {:error, term()}
  defdelegate start_session(session_id, opts), to: Phoenix.SessionProcess.ProcessSupervisor

  @doc """
  Deprecated: Use `start_session/1` instead.

  This function is kept for backward compatibility but will be removed in a future version.
  """
  @deprecated "Use start_session/1 instead"
  @spec start(binary()) :: {:ok, pid()} | {:error, term()}
  def start(session_id), do: start_session(session_id)

  @doc """
  Deprecated: Use `start_session/2` with options instead.

  ## Migration

      # Old
      start(session_id, MyModule)

      # New
      start_session(session_id, module: MyModule)
  """
  @deprecated "Use start_session/2 with module: option instead"
  @spec start(binary(), atom()) :: {:ok, pid()} | {:error, term()}
  def start(session_id, module), do: start_session(session_id, module: module)

  @doc """
  Deprecated: Use `start_session/2` with options instead.

  ## Migration

      # Old
      start(session_id, MyModule, args)

      # New
      start_session(session_id, module: MyModule, args: args)
  """
  @deprecated "Use start_session/2 with module: and args: options instead"
  @spec start(binary(), atom(), any()) :: {:ok, pid()} | {:error, term()}
  def start(session_id, module, arg), do: start_session(session_id, module: module, args: arg)

  @doc """
  Checks if a session process is currently running.

  ## Parameters
  - `session_id` - Unique binary identifier for the session

  ## Returns
  - `true` - Session process exists and is running
  - `false` - Session process does not exist

  ## Examples

      {:ok, _pid} = Phoenix.SessionProcess.start_session("user_123")
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

      {:ok, _pid} = Phoenix.SessionProcess.start_session("user_123")
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

      {:ok, _pid} = Phoenix.SessionProcess.start_session("user_123")

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

      {:ok, _pid} = Phoenix.SessionProcess.start_session("user_123")
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

      {:ok, _pid} = Phoenix.SessionProcess.start_session("user_123")
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
  - `session_id` - Session identifier (binary string)
  - `action_type` - Action type identifier (binary string, required)
  - `payload` - Action payload (any term, defaults to nil)
  - `meta` - Action metadata (keyword list, defaults to []):
    - `:reducers` - List of reducer names (atoms) to target explicitly. When specified:
      * Bypasses normal prefix routing entirely
      * Only calls the specified reducers
      * Passes full action type WITHOUT prefix stripping
      * Logs warning if any reducers don't exist
    - `:reducer_prefix` - Prefix to filter reducers by (when `:reducers` not specified)
    - `:async` - Route to handle_async/3 (true) or handle_action/2 (false, default)

  ## Action Type Stripping Behavior

  **Normal dispatch** (without `meta.reducers`):
  - Reducers with `@action_prefix "user"` receive action type with prefix stripped
  - Example: `dispatch(id, "user.reload")` → reducer sees `"reload"`

  **Explicit targeting** (with `meta.reducers`):
  - Action type is passed unchanged to specified reducers
  - Example: `dispatch(id, "user.reload", nil, reducers: [:user])` → reducer sees `"user.reload"`

  ## Returns
  - `:ok` - Action dispatched successfully
  - `{:error, {:session_not_found, session_id}}` - If session doesn't exist

  ## Examples

      # Simple action with prefix routing (type stripped)
      :ok = SessionProcess.dispatch(session_id, "user.reload")
      # → UserReducer receives "reload" (prefix stripped)

      # Action with payload
      :ok = SessionProcess.dispatch(session_id, "user.update", %{name: "Alice"})

      # Force specific reducers (type NOT stripped)
      :ok = SessionProcess.dispatch(session_id, "user.reload", nil, reducers: [:user, :cart])
      # → ONLY :user and :cart reducers called
      # → Both receive "user.reload" (prefix NOT stripped)

      # Warning logged for missing reducers
      :ok = SessionProcess.dispatch(session_id, "reload", nil, reducers: [:nonexistent])
      # → Logs warning: "Missing reducers: [:nonexistent]"

      # Use prefix filter
      :ok = SessionProcess.dispatch(session_id, "fetch-data", nil, reducer_prefix: "user")

      # Async action (routed to handle_async/3)
      :ok = SessionProcess.dispatch(session_id, "fetch-data", %{page: 1}, async: true)
  """
  @spec dispatch(binary(), String.t(), term(), keyword()) :: :ok | {:error, term()}
  def dispatch(session_id, action_type, payload \\ nil, meta \\ [])

  def dispatch(session_id, action_type, payload, meta)
      when is_binary(session_id) and is_binary(action_type) and is_list(meta) do
    alias Phoenix.SessionProcess.Action

    # Convert keyword list to map for Action struct
    meta_map = Map.new(meta)

    # Create action from components
    action = Action.new(action_type, payload, meta_map)

    case ProcessSupervisor.session_process_pid(session_id) do
      nil ->
        {:error, {:session_not_found, session_id}}

      _pid ->
        cast(session_id, {:dispatch_action, action})
        :ok
    end
  end

  def dispatch(_session_id, action_type, _payload, _meta) when not is_binary(action_type) do
    raise ArgumentError, """
    Action type must be a binary string, got: #{inspect(action_type)}

    Examples:
        dispatch(session_id, "user.reload")      # Correct
        dispatch(session_id, :reload)            # Wrong - atom
    """
  end

  def dispatch(_session_id, _action_type, _payload, meta) when not is_list(meta) do
    raise ArgumentError, """
    Action meta must be a keyword list, got: #{inspect(meta)}

    Examples:
        dispatch(session_id, "reload", nil, async: true)   # Correct
        dispatch(session_id, "reload", nil, %{async: true}) # Wrong - map
    """
  end

  @doc """
  Dispatch an action asynchronously (convenience alias).

  This is a convenience function that automatically adds `async: true` to the meta.
  It's equivalent to calling `dispatch(session_id, type, payload, [meta | async: true])`.

  When `async: true` is in the meta, the action will trigger `handle_async/3` callbacks
  in reducers that define them. The `handle_async` callback receives a dispatch function
  and must return a cancellation callback for internal lifecycle management.

  ## Parameters
  - `session_id` - Session identifier
  - `action_type` - Action type (binary string)
  - `payload` - Action payload (any term)
  - `meta` - Action metadata (keyword list, `async: true` will be added automatically)

  ## Returns
  - `:ok` - Action dispatched successfully
  - `{:error, {:session_not_found, session_id}}` - If session doesn't exist

  ## Examples

      # Equivalent to: dispatch(id, "user.reload", nil, async: true)
      :ok = SessionProcess.dispatch_async(session_id, "user.reload")

      # With payload - equivalent to: dispatch(id, "fetch_data", data, async: true)
      :ok = SessionProcess.dispatch_async(session_id, "fetch_data", %{page: 1})

      # With additional meta - equivalent to: dispatch(id, "reload", nil, [priority: :high, async: true])
      :ok = SessionProcess.dispatch_async(session_id, "reload", nil, priority: :high)
  """
  @spec dispatch_async(binary(), String.t(), term(), keyword()) ::
          :ok | {:error, term()}
  def dispatch_async(session_id, action_type, payload \\ nil, meta \\ [])

  def dispatch_async(session_id, action_type, payload, meta)
      when is_binary(session_id) and is_binary(action_type) and is_list(meta) do
    # Add async: true to meta and delegate to dispatch/4
    dispatch(session_id, action_type, payload, Keyword.put(meta, :async, true))
  end

  def dispatch_async(_session_id, action_type, _payload, _meta) when not is_binary(action_type) do
    raise ArgumentError, """
    Action type must be a binary string, got: #{inspect(action_type)}

    Examples:
        dispatch_async(session_id, "user.reload")      # Correct
        dispatch_async(session_id, :reload)            # Wrong - atom
    """
  end

  def dispatch_async(_session_id, _action_type, _payload, meta) when not is_list(meta) do
    raise ArgumentError, """
    Action meta must be a keyword list, got: #{inspect(meta)}

    Examples:
        dispatch_async(session_id, "reload", nil, async: true)   # Correct
        dispatch_async(session_id, "reload", nil, %{async: true}) # Wrong - map
    """
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
  Get the current state, optionally applying a selector function locally.

  This function retrieves the full state from the session process and optionally
  applies a selector function on the client side.

  ## Parameters
  - `session_id` - Session identifier
  - `selector` - Optional selector function `(state) -> selected_data`

  ## Returns
  - State or selected data
  - `{:error, reason}` - If session not found

  ## Examples

      # Get full state
      state = SessionProcess.get_state(session_id)

      # Get with inline selector (applied locally)
      user = SessionProcess.get_state(session_id, fn s -> s.user end)

  ## See Also

  - `select_state/2` - Apply selector on server side (more efficient for large states)
  """
  @spec get_state(binary(), function() | nil) :: any()
  def get_state(session_id, selector \\ nil) do
    case call(session_id, :get_state) do
      {:ok, state} when is_nil(selector) ->
        state

      {:ok, state} when is_function(selector, 1) ->
        selector.(state)

      error ->
        error
    end
  end

  @doc """
  Select state using a selector function applied on the server side.

  This function sends the selector to the session process where it is applied,
  returning only the selected data. This is more efficient than `get_state/2`
  when dealing with large state objects, as it avoids transferring the entire
  state over the process boundary.

  ## Parameters
  - `session_id` - Session identifier
  - `selector` - Selector function `(state) -> selected_data` (must be a function reference or anonymous function)

  ## Returns
  - Selected data from state
  - `{:error, reason}` - If session not found

  ## Examples

      # Select specific field (server-side selection)
      user = SessionProcess.select_state(session_id, fn s -> s.user end)

      # Select nested data
      cart_count = SessionProcess.select_state(session_id, fn s -> length(s.cart) end)

      # Select computed value
      total = SessionProcess.select_state(session_id, fn s ->
        Enum.reduce(s.cart, 0, fn item, acc -> acc + item.price end)
      end)

  ## Performance Note

  Use `select_state/2` instead of `get_state/2` when:
  - State is large and you only need a small portion
  - You want to compute derived values on the server side
  - You want to minimize data transfer between processes
  """
  @spec select_state(binary(), function()) :: any()
  def select_state(session_id, selector) when is_function(selector, 1) do
    case call(session_id, {:select_state, selector}) do
      {:ok, selected} -> selected
      error -> error
    end
  end

  @doc """
  Defines a reducer module for managing state slices.

  ## Usage

      defmodule MyApp.Reducers.UserReducer do
        use Phoenix.SessionProcess, :reducer
        alias Phoenix.SessionProcess.Action

        @name :user
        @action_prefix "user"

        def init_state do
          %{users: [], loading: false, query: nil}
        end

        @throttle {"fetch-list", "3000ms"}
        def handle_action(%Action{type: "fetch-list"}, state) do
          # Throttled: Only executes once per 3 seconds
          %{state | loading: true}
        end

        @debounce {"update-query", "500ms"}
        def handle_action(%Action{type: "update-query", payload: query}, state) do
          # Debounced: Waits 500ms after last call
          %{state | query: query}
        end

        def handle_async(%Action{type: "load", payload: %{page: page}}, dispatch, _state) do
          # Async action with dispatch callback
          # dispatch signature: dispatch(type, payload \\ nil, meta \\ [])
          # Must return cancellation function
          task = Task.async(fn ->
            data = fetch_data(page)
            dispatch.("load_success", data)
          end)

          fn -> Task.shutdown(task, :brutal_kill) end
        end
      end

  ## Callbacks

  - `init_state/0` - Define initial state for this reducer's slice (optional, defaults to `%{}`)
  - `handle_action/2` - Handle synchronous actions (receives Action struct), return updated state
  - `handle_async/3` - Handle async actions with dispatch callback, return cancellation function `(() -> any())`
    - dispatch signature: `dispatch(type, payload \\ nil, meta \\ [])` where type is binary, meta is keyword list
    - Default implementation returns `fn -> nil end`

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
      @before_compile Phoenix.SessionProcess.ReducerCompiler

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

      - `action` - The action to process (Action struct with type, payload, meta)
      - `state` - The current state slice for this reducer

      ## Returns

      - `new_state` - The updated state slice

      ## Examples

          alias Phoenix.SessionProcess.Action

          def handle_action(%Action{type: "increment"}, state) do
            %{state | count: state.count + 1}
          end

          def handle_action(%Action{type: "set_user", payload: user}, state) do
            %{state | current_user: user}
          end

          def handle_action(%Action{type: "update", payload: data, meta: meta}, state) do
            priority = Map.get(meta, :priority, :normal)
            %{state | data: data, priority: priority}
          end
      """
      def handle_action(_action, state), do: state

      @doc """
      Handle asynchronous actions with dispatch callback.

      Override this function for actions that require async operations.
      The dispatch callback allows you to dispatch new actions from async context.

      ## Parameters

      - `action` - The action to process (Action struct)
      - `dispatch` - Callback function to dispatch new actions with signature:
        - `dispatch.(type)` - Dispatch action with type only
        - `dispatch.(type, payload)` - Dispatch action with type and payload
        - `dispatch.(type, payload, meta)` - Dispatch action with type, payload, and meta (keyword list)
      - `state` - The current state slice for this reducer

      ## Returns

      - `cancel_fn` - A cancellation function `(() -> any())` that will be called if the action needs to be cancelled
      - Default implementation returns `fn -> nil end` (no-op cancellation)

      ## Examples

          def handle_async(%Action{type: "fetch_user", payload: id}, dispatch, state) do
            task = Task.async(fn ->
              user = API.fetch_user(id)
              dispatch.("fetch_user_success", user)
            rescue
              error ->
                dispatch.("fetch_user_error", %{error: error})
            end)

            # Return cancellation function
            fn -> Task.shutdown(task, :brutal_kill) end
          end

          # With meta
          def handle_async(%Action{type: "load_data"}, dispatch, state) do
            task = Task.async(fn ->
              data = API.load_data()
              dispatch.("load_data_success", data, priority: :high)
            end)

            fn -> Task.shutdown(task, :brutal_kill) end
          end

          # Simple case: no cancellation needed
          def handle_async(%Action{type: "log", payload: msg}, _dispatch, _state) do
            Logger.info(msg)
            fn -> nil end
          end
      """

      # NOTE: No default implementation for handle_async/3
      # Only export handle_async/3 if explicitly defined by the reducer
      # This ensures function_exported?(module, :handle_async, 3) accurately reflects intent

      defoverridable init_state: 0, handle_action: 2
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
  defmacro __using__(:process) do
    quote do
      use GenServer
      alias Phoenix.SessionProcess.Action

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
        # Call user's initialization callback
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
          _redux_subscriptions: [],
          _redux_middleware: [],
          _redux_history: [],
          _redux_max_history: 100,
          # Throttle/debounce state
          _redux_throttle_state: %{},
          _redux_debounce_timers: %{},
          # Cancelled action refs
          _cancelled_refs: MapSet.new(),
          # Async action cancel functions
          _async_cancel_fns: %{}
        }

        {:ok, state}
      end

      @doc """
      Initialize your application's state.

      Override this callback to provide your initial state as a map.

      ## Examples

          def init_state(_arg) do
            %{count: 0, user: nil, items: []}
          end

          def init_state(user_id) do
            %{user_id: user_id, cart: [], preferences: %{}}
          end
      """
      def init_state(_arg), do: %{}

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
        # Check if action has been cancelled
        cancel_ref = get_in(action.meta, [:cancel_ref])

        if cancel_ref && MapSet.member?(state._cancelled_refs, cancel_ref) do
          # Action was cancelled, remove from cancelled set and skip processing
          new_state = %{state | _cancelled_refs: MapSet.delete(state._cancelled_refs, cancel_ref)}
          {:noreply, new_state}
        else
          # Process action normally
          new_state = dispatch_with_reducers(action, state)
          {:noreply, new_state}
        end
      end

      @impl true
      def handle_cast({:cancel_action, ref}, state) do
        # Call the cancel function if it exists
        cancel_fns = Map.get(state, :_async_cancel_fns, %{})

        case Map.get(cancel_fns, ref) do
          nil ->
            # No cancel function, just mark as cancelled
            new_state = %{state | _cancelled_refs: MapSet.put(state._cancelled_refs, ref)}
            {:noreply, new_state}

          cancel_fn when is_function(cancel_fn, 0) ->
            # Call the cancel function
            cancel_fn.()

            # Remove cancel function and mark as cancelled
            new_cancel_fns = Map.delete(cancel_fns, ref)

            new_state = %{
              state
              | _cancelled_refs: MapSet.put(state._cancelled_refs, ref),
                _async_cancel_fns: new_cancel_fns
            }

            {:noreply, new_state}
        end
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
      # State Access
      # ========================================================================

      @impl true
      def handle_call(:get_state, _from, state) do
        {:reply, {:ok, state.app_state}, state}
      end

      @impl true
      def handle_call({:select_state, selector}, _from, state) when is_function(selector, 1) do
        selected = selector.(state.app_state)
        {:reply, {:ok, selected}, state}
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

      # Strip action prefix before passing to reducer if reducer has a prefix
      defp strip_action_prefix(action, reducer_prefix, skip_strip \\ false) do
        # When using meta.reducers for explicit targeting, don't strip prefix
        cond do
          skip_strip ->
            action

          is_nil(reducer_prefix) or reducer_prefix == "" ->
            # No prefix or catch-all reducer, pass unchanged
            action

          true ->
            # Try to strip matching prefix
            case String.split(action.type, ".", parts: 2) do
              [^reducer_prefix, local_type] ->
                %{action | type: local_type}

              _ ->
                # Prefix doesn't match, keep as-is
                action
            end
        end
      end

      # credo:disable-for-lines:60 Credo.Check.Refactor.Nesting
      defp apply_combined_reducer(module, action, slice_key, app_state, internal_state) do
        alias Phoenix.SessionProcess.ActionRateLimiter

        # Get the state slice for this reducer
        slice_state = Map.get(app_state, slice_key, %{})

        # Get reducer's action prefix and strip it from action type
        # Skip stripping when using explicit reducer targeting (meta.reducers)
        reducer_prefix = module.__reducer_action_prefix__()
        skip_strip = not is_nil(Action.target_reducers(action))
        local_action = strip_action_prefix(action, reducer_prefix, skip_strip)

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
            {new_slice_state, new_internal_state_with_cancel} =
              if function_exported?(module, :handle_async, 3) and async_action?(action) do
                # Async action - provide dispatch callback
                # Create a dispatch function that captures self() PID
                session_pid = self()

                dispatch_fn = &__async_dispatch__(session_pid, &1, &2, &3)

                # handle_async returns cancel function, not state
                # Pass local_action with stripped prefix
                cancel_fn = module.handle_async(local_action, dispatch_fn, slice_state)

                # Store cancel function in internal state if action has cancel_ref
                new_internal_with_cancel =
                  case get_in(action.meta, [:cancel_ref]) do
                    nil ->
                      internal_state

                    ref ->
                      cancel_fns = Map.get(internal_state, :_async_cancel_fns, %{})
                      new_cancel_fns = Map.put(cancel_fns, ref, cancel_fn)
                      Map.put(internal_state, :_async_cancel_fns, new_cancel_fns)
                  end

                # Async actions don't update state directly - state unchanged
                {slice_state, new_internal_with_cancel}
              else
                # Synchronous action updates state
                # Pass local_action with stripped prefix
                new_state = module.handle_action(local_action, slice_state)
                {new_state, internal_state}
              end

            # Update app_state with new slice
            new_app_state = Map.put(app_state, slice_key, new_slice_state)

            # Record throttle if needed
            new_internal_state =
              ActionRateLimiter.record_throttle(module, action, new_internal_state_with_cancel)

            {new_app_state, new_internal_state}
          end
        end
      end

      defp async_action?(%Action{} = action) do
        # Check if action has async metadata flag
        Action.async?(action)
      end

      defp async_action?(%{type: type}) when is_binary(type),
        do: String.ends_with?(type, "_async")

      defp async_action?(_), do: false

      # Helper function for async dispatch callback
      # Accepts: dispatch(type, payload \\ nil, meta \\ [])
      defp __async_dispatch__(session_pid, type, payload \\ nil, meta \\ [])

      defp __async_dispatch__(session_pid, type, payload, meta)
           when is_binary(type) and is_list(meta) do
        meta_map = Map.new(meta)
        new_action = Action.new(type, payload, meta_map)
        GenServer.cast(session_pid, {:dispatch_action, new_action})
      end

      defp __async_dispatch__(_session_pid, type, _payload, _meta) when not is_binary(type) do
        raise ArgumentError, """
        dispatch type must be a binary string, got: #{inspect(type)}

        Examples:
            dispatch.("user.reload")           # Correct
            dispatch.(:reload)                 # Wrong - atom
        """
      end

      defp __async_dispatch__(_session_pid, _type, _payload, meta) when not is_list(meta) do
        raise ArgumentError, """
        dispatch meta must be a keyword list, got: #{inspect(meta)}

        Examples:
            dispatch.("reload", nil, async: true)   # Correct
            dispatch.("reload", nil, %{async: true}) # Wrong - map
        """
      end

      defp dispatch_with_reducers(action, state) do
        # Action is already an Action struct from dispatch/4
        old_app_state = state.app_state

        # Determine which reducers should handle this action based on routing metadata
        reducers_to_apply = filter_reducers_for_action(action, state._redux_reducers)

        # Apply filtered reducers (only combined reducers from combined_reducers/0)
        {new_app_state, new_internal_state} =
          Enum.reduce(reducers_to_apply, {old_app_state, state}, fn
            {_name, {:combined, module, slice_key, _prefix}},
            {acc_app_state, acc_internal_state} ->
              {updated_app_state, updated_internal_state} =
                apply_combined_reducer(
                  module,
                  action,
                  slice_key,
                  acc_app_state,
                  acc_internal_state
                )

              {updated_app_state, updated_internal_state}
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
        alias Phoenix.SessionProcess.Action
        require Logger

        # Check explicit reducer targeting (highest priority)
        case Action.target_reducers(action) do
          nil ->
            # No explicit targets, check for prefix routing
            filter_by_prefix(action, all_reducers)

          target_list when is_list(target_list) ->
            # Explicit list of reducer names to target
            filtered_reducers = Enum.filter(all_reducers, fn {name, _} -> name in target_list end)

            # Log warning if any requested reducers are missing
            requested_names = MapSet.new(target_list)
            found_names = MapSet.new(Enum.map(filtered_reducers, fn {name, _} -> name end))
            missing = MapSet.difference(requested_names, found_names)

            if MapSet.size(missing) > 0 do
              Logger.warning("""
              Action dispatched with meta.reducers targeting non-existent reducers.
              Action type: #{action.type}
              Missing reducers: #{inspect(MapSet.to_list(missing))}
              Available reducers: #{inspect(Map.keys(all_reducers))}
              """)
            end

            filtered_reducers
        end
      end

      # Filter reducers by prefix (explicit or inferred from action type)
      defp filter_by_prefix(action, all_reducers) do
        alias Phoenix.SessionProcess.Action

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
      defp infer_prefix_from_action(%Action{type: type})
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
                     handle_call: 3,
                     handle_cast: 2,
                     handle_info: 2
    end
  end

  @doc false
  def __on_reducer_definition__(env, _kind, _name, _args, _guards, _body) do
    alias Phoenix.SessionProcess.ReducerCompiler

    module = env.module

    # Check for @throttle attribute
    if throttle = Module.get_attribute(module, :throttle) do
      ReducerCompiler.register_throttle(module, throttle)
      Module.delete_attribute(module, :throttle)
    end

    # Check for @debounce attribute
    if debounce = Module.get_attribute(module, :debounce) do
      ReducerCompiler.register_debounce(module, debounce)
      Module.delete_attribute(module, :debounce)
    end
  end
end
