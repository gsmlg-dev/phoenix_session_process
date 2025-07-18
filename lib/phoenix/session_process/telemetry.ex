defmodule Phoenix.SessionProcess.Telemetry do
  @moduledoc """
  Telemetry events for Phoenix.SessionProcess.

  This module provides telemetry events that can be used to monitor
  session lifecycle, performance, and errors.

  ## Events

  The following telemetry events are emitted:

  ### Session Lifecycle
  - `[:phoenix, :session_process, :start]` - When a session starts
  - `[:phoenix, :session_process, :stop]` - When a session stops
  - `[:phoenix, :session_process, :start_error]` - When session start fails

  ### Communication
  - `[:phoenix, :session_process, :call]` - When a call is made to a session
  - `[:phoenix, :session_process, :cast]` - When a cast is made to a session
  - `[:phoenix, :session_process, :communication_error]` - When communication fails

  ### Cleanup
  - `[:phoenix, :session_process, :cleanup]` - When a session is cleaned up
  - `[:phoenix, :session_process, :cleanup_error]` - When cleanup fails

  All events include the following metadata:
  - `session_id` - The session ID
  - `module` - The session module
  - `pid` - The process PID (when applicable)
  - `measurements` - Performance measurements
  """

  @doc """
  Emits a telemetry event for session start.
  """
  @spec emit_session_start(String.t(), atom(), pid(), keyword()) :: :ok
  def emit_session_start(session_id, module, pid, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :start],
      Map.new(measurements),
      %{session_id: session_id, module: module, pid: pid}
    )
  end

  @doc """
  Emits a telemetry event for session stop.
  """
  @spec emit_session_stop(String.t(), atom(), pid(), keyword()) :: :ok
  def emit_session_stop(session_id, module, pid, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :stop],
      Map.new(measurements),
      %{session_id: session_id, module: module, pid: pid}
    )
  end

  @doc """
  Emits a telemetry event for session start error.
  """
  @spec emit_session_start_error(String.t(), atom(), any(), keyword()) :: :ok
  def emit_session_start_error(session_id, module, reason, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :start_error],
      Map.new(measurements),
      %{session_id: session_id, module: module, reason: reason}
    )
  end

  @doc """
  Emits a telemetry event for session call.
  """
  @spec emit_session_call(String.t(), atom(), pid(), any(), keyword()) :: :ok
  def emit_session_call(session_id, module, pid, message, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :call],
      Map.new(measurements),
      %{session_id: session_id, module: module, pid: pid, message: message}
    )
  end

  @doc """
  Emits a telemetry event for session cast.
  """
  @spec emit_session_cast(String.t(), atom(), pid(), any(), keyword()) :: :ok
  def emit_session_cast(session_id, module, pid, message, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :cast],
      Map.new(measurements),
      %{session_id: session_id, module: module, pid: pid, message: message}
    )
  end

  @doc """
  Emits a telemetry event for communication error.
  """
  @spec emit_communication_error(String.t(), atom(), any(), any(), keyword()) :: :ok
  def emit_communication_error(session_id, module, operation, reason, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :communication_error],
      Map.new(measurements),
      %{session_id: session_id, module: module, operation: operation, reason: reason}
    )
  end

  @doc """
  Emits a telemetry event for session cleanup.
  """
  @spec emit_session_cleanup(String.t(), atom(), pid(), keyword()) :: :ok
  def emit_session_cleanup(session_id, module, pid, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :cleanup],
      Map.new(measurements),
      %{session_id: session_id, module: module, pid: pid}
    )
  end

  @doc """
  Emits a telemetry event for session cleanup error.
  """
  @spec emit_session_cleanup_error(String.t(), atom(), any(), keyword()) :: :ok
  def emit_session_cleanup_error(session_id, module, reason, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :cleanup_error],
      Map.new(measurements),
      %{session_id: session_id, module: module, reason: reason}
    )
  end

  @doc """
  Measures the execution time of a function and emits telemetry events.
  """
  @spec measure(String.t(), atom(), fun()) :: {:ok, any()} | {:error, any()}
  def measure(session_id, operation, fun) do
    start_time = System.monotonic_time()
    
    try do
      result = fun.()
      end_time = System.monotonic_time()
      duration = end_time - start_time
      
      :telemetry.execute(
        [:phoenix, :session_process, operation],
        %{duration: duration},
        %{session_id: session_id}
      )
      
      result
    rescue
      error ->
        end_time = System.monotonic_time()
        duration = end_time - start_time
        
        :telemetry.execute(
          [:phoenix, :session_process, :error],
          %{duration: duration},
          %{session_id: session_id, operation: operation, error: error}
        )
        
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        end_time = System.monotonic_time()
        duration = end_time - start_time
        
        :telemetry.execute(
          [:phoenix, :session_process, :error],
          %{duration: duration},
          %{session_id: session_id, operation: operation, kind: kind, reason: reason}
        )
        
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end
end