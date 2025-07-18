defmodule Phoenix.SessionProcess.ProcessSupervisor do
  require Logger

  # Automatically defines child_spec/1
  use DynamicSupervisor

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_child(worker, worker_arg) do
    worker_spec = {worker, worker_arg}
    Logger.debug("Start Child Worker: #{inspect(worker_spec)}")
    DynamicSupervisor.start_child(__MODULE__, worker_spec)
  end

  def terminate_child(pid) do
    Logger.debug("Terminating Child Worker: #{inspect(pid)}")
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_session(session_id) do
    with :ok <- validate_session_id(session_id),
         :ok <- check_session_limits() do
      Logger.debug("Start Session: #{inspect(session_id)}")
      module = Phoenix.SessionProcess.Config.session_process()
      spec = {module, [name: child_name(session_id)]}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Phoenix.SessionProcess.Cleanup.schedule_session_cleanup(session_id)
          {:ok, pid}

        {:ok, pid, _info} ->
          Phoenix.SessionProcess.Cleanup.schedule_session_cleanup(session_id)
          {:ok, pid}

        other ->
          other
      end
    end
  end

  def start_session(session_id, module) do
    with :ok <- validate_session_id(session_id),
         :ok <- check_session_limits() do
      Logger.debug("Start Session: #{inspect(session_id)}")
      spec = {module, [name: child_name(session_id)]}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Phoenix.SessionProcess.Cleanup.schedule_session_cleanup(session_id)
          {:ok, pid}

        {:ok, pid, _info} ->
          Phoenix.SessionProcess.Cleanup.schedule_session_cleanup(session_id)
          {:ok, pid}

        other ->
          other
      end
    end
  end

  def start_session(session_id, module, arg) do
    with :ok <- validate_session_id(session_id),
         :ok <- check_session_limits() do
      Logger.debug("Start Session: #{inspect(session_id)}")
      spec = {module, [name: child_name(session_id), arg: arg]}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Phoenix.SessionProcess.Cleanup.schedule_session_cleanup(session_id)
          {:ok, pid}

        {:ok, pid, _info} ->
          Phoenix.SessionProcess.Cleanup.schedule_session_cleanup(session_id)
          {:ok, pid}

        other ->
          other
      end
    end
  end

  @spec session_process_started?(binary()) :: boolean()
  def session_process_started?(session_id) do
    session_id
    |> session_process_pid()
    |> is_pid()
  end

  @spec terminate_session(binary()) :: :ok | {:error, :not_found}
  def terminate_session(session_id) do
    Logger.debug("End Session: #{inspect(session_id)}")

    case session_process_pid(session_id) do
      nil -> {:error, :not_found}
      pid -> terminate_child(pid)
    end
  end

  def call_on_session(session_id, request, timeout \\ 15_000) do
    case session_process_pid(session_id) do
      nil -> {:error, :session_not_found}
      pid -> GenServer.call(pid, request, timeout)
    end
  end

  def cast_on_session(session_id, request) do
    case session_process_pid(session_id) do
      nil -> {:error, :session_not_found}
      pid -> GenServer.cast(pid, request)
    end
  end

  @spec child_name(binary()) :: {:via, Registry, {Phoenix.SessionProcess.Registry, binary()}}
  def child_name(session_id) do
    {:via, Registry, {Phoenix.SessionProcess.Registry, session_id}}
  end

  @spec session_process_pid(binary()) :: nil | pid()
  def session_process_pid(session_id) do
    case {Phoenix.SessionProcess.Registry, session_id} |> Registry.whereis_name() do
      :undefined -> nil
      pid -> pid
    end
  end

  defp validate_session_id(session_id) do
    if Phoenix.SessionProcess.Config.valid_session_id?(session_id) do
      :ok
    else
      {:error, :invalid_session_id}
    end
  end

  defp check_session_limits() do
    max_sessions = Phoenix.SessionProcess.Config.max_sessions()
    current_sessions = Registry.count(Phoenix.SessionProcess.Registry)

    if current_sessions < max_sessions do
      :ok
    else
      {:error, :session_limit_reached}
    end
  end
end
