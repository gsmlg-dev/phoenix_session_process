defmodule Phoenix.SessionProcess.ProcessSupervisor do
  require Logger

  # Automatically defines child_spec/1
  use DynamicSupervisor

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_child(workder, worker_arg) do
    workder_spec = {workder, worker_arg}
    Logger.debug("Start Child Worker: #{inspect(workder_spec)}")
    DynamicSupervisor.start_child(__MODULE__, workder_spec)
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
    Logger.debug("Start Session: #{inspect(session_id)}")
    module = Application.get_env(:phoenix_session_process, :session_process)
    spec = {module, name: child_name(session_id)}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def start_session(session_id, module) do
    Logger.debug("Start Session: #{inspect(session_id)}")
    spec = {module, name: child_name(session_id)}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def start_session(session_id, module, arg) do
    Logger.debug("Start Session: #{inspect(session_id)}")
    spec = {module, name: child_name(session_id), arg: arg}
    DynamicSupervisor.start_child(__MODULE__, spec)
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
    session_id
    |> session_process_pid()
    |> terminate_child()
  end

  def call_on_session(session_id, request, timeout \\ 15_000) do
    session_id
    |> session_process_pid()
    |> GenServer.call(request, timeout)
  end

  def cast_on_session(session_id, request) do
    session_id
    |> session_process_pid()
    |> GenServer.cast(request)
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
end
