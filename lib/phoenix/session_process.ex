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
        use Phoenix.SessionProcess, :process_link

        @impl true
        def init(_init_arg) do
          {:ok, %{user: nil, live_views: []}}
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
  @spec list_session :: [{binary(), pid()}, ...]
  def list_session do
    Registry.select(Phoenix.SessionProcess.Registry, [
      {{:":$1", :":$2", :_}, [], [{{:":$1", :":$2"}}]}
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
        case Registry.lookup(Phoenix.SessionProcess.Registry, pid) do
          [{_, module}] -> module
          _ -> Phoenix.SessionProcess.Config.session_process()
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
    Registry.select(Phoenix.SessionProcess.Registry, [
      {{:"$1", :"$2", :"$_"}, [], [{{:"$1", :"$2", :"$_"}}]}
    ])
    |> Enum.filter(fn {_session_id, _pid, mod} -> mod == module end)
    |> Enum.map(fn {session_id, _pid, _mod} -> session_id end)
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
    case Phoenix.SessionProcess.ProcessSupervisor.session_process_pid(session_id) do
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

    memory_usage =
      if total_sessions > 0 do
        sessions
        |> Enum.map(fn {_session_id, pid} ->
          case :erlang.process_info(pid, :memory) do
            {:memory, memory} -> memory
            _ -> 0
          end
        end)
        |> Enum.sum()
      else
        0
      end

    avg_memory = if total_sessions > 0, do: div(memory_usage, total_sessions), else: 0

    %{
      total_sessions: total_sessions,
      memory_usage: memory_usage,
      avg_memory_per_session: avg_memory
    }
  end

  defmacro __using__(:process) do
    quote do
      use GenServer

      def start_link(opts) do
        arg = Keyword.get(opts, :arg, %{})
        name = Keyword.get(opts, :name)
        GenServer.start_link(__MODULE__, arg, name: name)
      end

      def get_session_id do
        current_pid = self()

        Registry.select(Phoenix.SessionProcess.Registry, [
          {{:":$1", :":$2", :_}, [{:==, :":$2", current_pid}], [{{:":$1", :":$2"}}]}
        ])
        |> Enum.at(0)
        |> elem(0)
      end
    end
  end

  defmacro __using__(:process_link) do
    quote do
      use GenServer

      def start_link(opts) do
        args = Keyword.get(opts, :args, %{})
        name = Keyword.get(opts, :name)
        GenServer.start_link(__MODULE__, args, name: name)
      end

      def get_session_id do
        current_pid = self()

        Registry.select(Phoenix.SessionProcess.Registry, [
          {{:":$1", :":$2", :_}, [{:==, :":$2", current_pid}], [{{:":$1", :":$2"}}]}
        ])
        |> Enum.at(0)
        |> elem(0)
      end

      def handle_cast({:monitor, pid}, state) do
        new_state =
          state |> Map.update(:__live_view__, [pid], fn views -> [pid | views] end)

        Process.monitor(pid)
        {:noreply, new_state}
      end

      def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
        new_state =
          state
          |> Map.update(:__live_view__, [], fn views -> views |> Enum.filter(&(&1 != pid)) end)

        {:noreply, new_state}
      end

      def terminate(_reason, state) do
        state
        |> Map.get(:__live_view__, [])
        |> Enum.each(&Process.send_after(&1, :session_expired, 0))
      end
    end
  end
end
