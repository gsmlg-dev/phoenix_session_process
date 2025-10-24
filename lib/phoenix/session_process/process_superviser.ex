defmodule Phoenix.SessionProcess.ProcessSupervisor do
  @moduledoc """
  Dynamic supervisor for managing individual session processes.

  This supervisor is responsible for the lifecycle management of all session processes.
  It handles starting, stopping, and monitoring session processes dynamically as they
  are created and destroyed during application runtime.

  ## Key Responsibilities

  ### Process Management
  - Dynamically starts session processes on demand
  - Terminates session processes when requested or when they expire
  - Tracks all active session processes
  - Provides process lookup by session ID

  ### Registry Integration
  - Registers each session process in `Phoenix.SessionProcess.Registry`
  - Ensures unique session ID to process mappings
  - Enables fast process lookup for communication

  ### Telemetry Integration
  - Emits telemetry events for all operations
  - Tracks session lifecycle metrics
  - Monitors performance and error rates

  ## Public API

  This module provides the main internal API for session process management:

  ### Session Lifecycle
  - `start_session/1-3` - Start new session processes
  - `terminate_session/1` - Terminate specific session
  - `session_process_started?/1` - Check if session exists
  - `session_process_pid/1` - Get process PID for session ID

  ### Process Communication
  - `call_session/4` - GenServer call to session process
  - `cast_session/3` - GenServer cast to session process

  ### Administrative Functions
  - `start_child/2` - Generic child process starter
  - `terminate_child/1` - Generic child process terminator
  - `count_children/0` - Get count of active sessions

  ## Process Strategy

  Uses `:one_for_one` strategy which means:
  - If a session process crashes, only that process is restarted
  - Other session processes continue unaffected
  - Provides isolation between user sessions

  ## Error Handling

  All operations include comprehensive error handling:
  - Invalid session IDs are rejected
  - Session limits are enforced
  - Process failures are logged and monitored
  - Telemetry events are emitted for debugging

  ## Performance Considerations

  - Registry provides O(1) session lookups
  - Dynamic supervisor scales to thousands of sessions
  - Each session process is isolated and lightweight
  - Memory usage scales linearly with session count

  ## Example Usage

  This module is typically used internally by the main `Phoenix.SessionProcess` API,
  but can also be used directly for advanced scenarios:

      # Start a session process
      {:ok, pid} = ProcessSupervisor.start_session("user_123")

      # Check if session exists
      started? = ProcessSupervisor.session_process_started?("user_123")

      # Terminate a session
      :ok = ProcessSupervisor.terminate_session("user_123")
  """

  require Logger

  # Automatically defines child_spec/1
  use DynamicSupervisor

  alias Phoenix.SessionProcess.{Error, Telemetry}

  @doc """
  Starts the process supervisor.

  This function is typically called by the top-level supervisor when starting
  the Phoenix.SessionProcess system.

  ## Parameters

  - `init_arg` - Initialization arguments (unused, kept for compatibility)

  ## Returns

  - `{:ok, pid()}` - Supervisor started successfully
  - `{:error, reason}` - Failed to start supervisor
  - `:ignore` - Supervisor should be ignored
  """
  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a child process using the dynamic supervisor.

  This is a generic function that can start any child process under this supervisor.
  It's primarily used internally for starting session processes.

  ## Parameters

  - `worker` - The module to start as a child process
  - `worker_arg` - Arguments to pass to the child process

  ## Returns

  - `{:ok, pid()}` - Child process started successfully
  - `{:error, reason}` - Failed to start child process
  """
  def start_child(worker, worker_arg) do
    worker_spec = {worker, worker_arg}
    Phoenix.SessionProcess.Telemetry.emit_worker_start(worker_spec)
    DynamicSupervisor.start_child(__MODULE__, worker_spec)
  end

  @doc """
  Terminates a child process.

  ## Parameters

  - `pid` - The PID of the child process to terminate

  ## Returns

  - `:ok` - Child process terminated successfully
  - `{:error, reason}` - Failed to terminate child process
  """
  def terminate_child(pid) do
    Phoenix.SessionProcess.Telemetry.emit_worker_terminate(pid)
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  Initializes the dynamic supervisor.

  ## Parameters

  - `_init_arg` - Initialization arguments (unused)

  ## Returns

  - `{:ok, supervisor_config}` - Supervisor initialized successfully
  """
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a session process using the default configured module.

  ## Parameters

  - `session_id` - Unique identifier for the session

  ## Returns

  - `{:ok, pid()}` - Session process started successfully
  - `{:error, reason}` - Failed to start session process
  """
  def start_session(session_id) do
    start_session_with_module(session_id, Phoenix.SessionProcess.Config.session_process())
  end

  @doc """
  Starts a session process using a specific module.

  ## Parameters

  - `session_id` - Unique identifier for the session
  - `module` - Session process module to use

  ## Returns

  - `{:ok, pid()}` - Session process started successfully
  - `{:error, reason}` - Failed to start session process
  """
  def start_session(session_id, module) do
    start_session_with_module(session_id, module)
  end

  @doc """
  Starts a session process using a specific module with initialization arguments.

  ## Parameters

  - `session_id` - Unique identifier for the session
  - `module` - Session process module to use
  - `arg` - Initialization arguments for the session process

  ## Returns

  - `{:ok, pid()}` - Session process started successfully
  - `{:error, reason}` - Failed to start session process
  """
  def start_session(session_id, module, arg) do
    start_session_with_module(session_id, module, arg)
  end

  @doc """
  Checks if a session process has been started for the given session ID.

  ## Parameters

  - `session_id` - The session ID to check

  ## Returns

  - `boolean()` - `true` if the session process exists, `false` otherwise
  """
  @spec session_process_started?(binary()) :: boolean()
  def session_process_started?(session_id) do
    session_id
    |> session_process_pid()
    |> is_pid()
  end

  @doc """
  Terminates a session process for the given session ID.

  This function gracefully shuts down the session process and emits telemetry events
  for monitoring and debugging purposes.

  ## Parameters

  - `session_id` - The session ID whose process should be terminated

  ## Returns

  - `:ok` - Session process terminated successfully
  - `{:error, :not_found}` - Session process not found

  ## Side Effects

  - Emits telemetry event for session termination
  - Removes process from registry
  - Logs the termination operation
  """
  @spec terminate_session(binary()) :: :ok | {:error, :not_found}
  def terminate_session(session_id) do
    Phoenix.SessionProcess.Telemetry.emit_session_end_event(session_id)
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
      Phoenix.SessionProcess.Telemetry.emit_session_start_event(session_id)

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

  defp check_session_limits do
    max_sessions = Phoenix.SessionProcess.Config.max_sessions()
    current_sessions = Registry.count(Phoenix.SessionProcess.Registry)

    if current_sessions < max_sessions do
      :ok
    else
      {:error, :session_limit_reached}
    end
  end
end
