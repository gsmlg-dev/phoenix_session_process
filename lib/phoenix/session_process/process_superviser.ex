defmodule Phoenix.SessionProcess.ProcessSupervisor do
  require Logger

  # Automatically defines child_spec/1
  use DynamicSupervisor

  alias Phoenix.SessionProcess.{Telemetry, Error}

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
    start_session_with_module(session_id, Phoenix.SessionProcess.Config.session_process())
  end

  def start_session(session_id, module) do
    start_session_with_module(session_id, module)
  end

  def start_session(session_id, module, arg) do
    start_session_with_module(session_id, module, arg)
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
    start_time = System.monotonic_time()

    case session_process_pid(session_id) do
      nil ->
        Error.session_not_found(session_id)

      pid ->
        module = get_session_module(pid)
        result = terminate_child(pid)
        duration = System.monotonic_time() - start_time

        case result do
          :ok ->
            Telemetry.emit_session_stop(session_id, module, pid, duration: duration)
            :ok

          error ->
            Telemetry.emit_session_cleanup_error(session_id, module, error, duration: duration)
            error
        end
    end
  end

  def call_on_session(session_id, request, timeout \\ 15_000) do
    start_time = System.monotonic_time()

    case session_process_pid(session_id) do
      nil ->
        Error.session_not_found(session_id)

      pid ->
        module = get_session_module(pid)
        do_call_on_session(session_id, pid, module, request, timeout, start_time)
    end
  end

  def cast_on_session(session_id, request) do
    start_time = System.monotonic_time()

    case session_process_pid(session_id) do
      nil ->
        Error.session_not_found(session_id)

      pid ->
        module = get_session_module(pid)
        do_cast_on_session(session_id, pid, module, request, start_time)
    end
  end

  defp do_call_on_session(session_id, pid, module, request, timeout, start_time) do
    try do
      result = GenServer.call(pid, request, timeout)
      duration = System.monotonic_time() - start_time
      Telemetry.emit_session_call(session_id, module, pid, request, duration: duration)
      result
    catch
      :exit, {:timeout, _} ->
        duration = System.monotonic_time() - start_time

        Telemetry.emit_communication_error(session_id, module, :call, :timeout,
          duration: duration
        )

        Error.timeout(timeout)

      :exit, reason ->
        duration = System.monotonic_time() - start_time
        Telemetry.emit_communication_error(session_id, module, :call, reason, duration: duration)
        Error.call_failed(module, :call, {request}, reason)
    end
  end

  defp do_cast_on_session(session_id, pid, module, request, start_time) do
    try do
      result = GenServer.cast(pid, request)
      duration = System.monotonic_time() - start_time
      Telemetry.emit_session_cast(session_id, module, pid, request, duration: duration)
      result
    catch
      :exit, reason ->
        duration = System.monotonic_time() - start_time
        Telemetry.emit_communication_error(session_id, module, :cast, reason, duration: duration)
        Error.cast_failed(module, :cast, {request}, reason)
    end
  end

  @spec child_name(binary()) :: {:via, Registry, {Phoenix.SessionProcess.Registry, binary()}}
  def child_name(session_id) do
    {:via, Registry, {Phoenix.SessionProcess.Registry, session_id}}
  end

  @spec session_process_pid(binary()) :: nil | pid()
  def session_process_pid(session_id) do
    case Registry.whereis_name({Phoenix.SessionProcess.Registry, session_id}) do
      :undefined -> nil
      pid -> pid
    end
  end

  defp start_session_with_module(session_id, module, arg \\ nil) do
    start_time = System.monotonic_time()

    with :ok <- validate_session_id(session_id),
         :ok <- check_session_limits() do
      Logger.debug("Start Session: #{inspect(session_id)}")

      worker_args =
        if arg, do: [name: child_name(session_id), arg: arg], else: [name: child_name(session_id)]

      spec = {module, worker_args}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} = result ->
          Registry.register(Phoenix.SessionProcess.Registry, pid, module)
          Phoenix.SessionProcess.Cleanup.schedule_session_cleanup(session_id)
          duration = System.monotonic_time() - start_time
          Telemetry.emit_session_start(session_id, module, pid, duration: duration)
          result

        {:ok, pid, _info} = result ->
          Registry.register(Phoenix.SessionProcess.Registry, pid, module)
          Phoenix.SessionProcess.Cleanup.schedule_session_cleanup(session_id)
          duration = System.monotonic_time() - start_time
          Telemetry.emit_session_start(session_id, module, pid, duration: duration)
          result

        {:error, {:already_started, pid}} = result ->
          duration = System.monotonic_time() - start_time
          Telemetry.emit_session_start(session_id, module, pid, duration: duration)
          result

        {:error, reason} = error ->
          duration = System.monotonic_time() - start_time
          Telemetry.emit_session_start_error(session_id, module, reason, duration: duration)
          error
      end
    else
      {:error, :invalid_session_id} ->
        duration = System.monotonic_time() - start_time

        Telemetry.emit_session_start_error(session_id, module, :invalid_session_id,
          duration: duration
        )

        Error.invalid_session_id(session_id)

      {:error, :session_limit_reached} ->
        max_sessions = Phoenix.SessionProcess.Config.max_sessions()
        duration = System.monotonic_time() - start_time

        Telemetry.emit_session_start_error(
          session_id,
          module,
          {:session_limit_reached, max_sessions},
          duration: duration
        )

        Error.session_limit_reached(max_sessions)
    end
  end

  defp get_session_module(pid) do
    case Registry.lookup(Phoenix.SessionProcess.Registry, pid) do
      [{_, module}] -> module
      _ -> Phoenix.SessionProcess.Config.session_process()
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
