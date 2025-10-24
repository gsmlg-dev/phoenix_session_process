defmodule Phoenix.SessionProcess do
  @moduledoc """
  Documentation for `Phoenix.SessionProcess`.

  Add superviser to process tree

      [
        ...
        {Phoenix.SessionProcess.Supervisor, []}
      ]

  Add this after the `:fetch_session` plug to generate a unique session ID.

      plug :fetch_session
      plug Phoenix.SessionProcess.SessionId

  Start a session process with a session ID.

      Phoenix.SessionProcess.start("session_id")

  This will start a session process using the module defined with

      config :phoenix_session_process, session_process: MySessionProcess

  Or you can start a session process with a specific module.

      Phoenix.SessionProcess.start("session_id", MySessionProcess)
      # or
      Phoenix.SessionProcess.start("session_id", MySessionProcess, arg)

  Check if a session process is started.

      Phoenix.SessionProcess.started?("session_id")

  Terminate a session process.

      Phoenix.SessionProcess.terminate("session_id")

  Genserver call on a session process.

      Phoenix.SessionProcess.call("session_id", request)

  Genserver cast on a session process.

      Phoenix.SessionProcess.cast("session_id", request)

  List all session processes.

      Phoenix.SessionProcess.list_session()
  """

  @spec start(binary()) :: {:ok, pid()} | {:error, term()}
  defdelegate start(session_id), to: Phoenix.SessionProcess.ProcessSupervisor, as: :start_session

  @doc """
  Start a session process with a specific module.

  ## Examples

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
  Start a session process with a specific module and initialization arguments.

  ## Examples

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

  @spec started?(binary()) :: boolean()
  defdelegate started?(session_id),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :session_process_started?

  @spec terminate(binary()) :: :ok | {:error, :not_found}
  defdelegate terminate(session_id),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :terminate_session

  @spec call(binary(), any(), :infinity | non_neg_integer()) :: {:ok, any()} | {:error, term()}
  defdelegate call(session_id, request, timeout \\ 15_000),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :call_on_session

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
  @spec list_session() :: [{binary(), pid()}, ...]
  def list_session() do
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
  @spec session_info() :: %{count: integer(), modules: list(module())}
  def session_info() do
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
  @spec session_stats() :: %{
          total_sessions: integer(),
          memory_usage: integer(),
          avg_memory_per_session: integer()
        }
  def session_stats() do
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

      def get_session_id() do
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

      def get_session_id() do
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
