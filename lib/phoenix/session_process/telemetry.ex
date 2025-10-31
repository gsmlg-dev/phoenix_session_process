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

  ### Process Management
  - `[:phoenix, :session_process, :worker_start]` - When a worker process starts
  - `[:phoenix, :session_process, :worker_terminate]` - When a worker process terminates
  - `[:phoenix, :session_process, :session_start]` - When a session process starts
  - `[:phoenix, :session_process, :session_end]` - When a session process ends

  ### Cleanup
  - `[:phoenix, :session_process, :auto_cleanup]` - When a session is auto-cleaned up
  - `[:phoenix, :session_process, :cleanup]` - When a session is cleaned up
  - `[:phoenix, :session_process, :cleanup_error]` - When cleanup fails

  ### Redux State Management
  - `[:phoenix, :session_process, :redux, :dispatch]` - When a Redux action is dispatched
  - `[:phoenix, :session_process, :redux, :subscribe]` - When a subscription is created
  - `[:phoenix, :session_process, :redux, :unsubscribe]` - When a subscription is removed
  - `[:phoenix, :session_process, :redux, :notification]` - When subscriptions are notified
  - `[:phoenix, :session_process, :redux, :selector_cache_hit]` - When selector cache is hit
  - `[:phoenix, :session_process, :redux, :selector_cache_miss]` - When selector cache misses
  All events include the following metadata:
  - `session_id` - The session ID (when applicable)
  - `module` - The session module
  - `pid` - The process PID (when applicable)
  - `worker_spec` - Worker specification details (for worker events)
  - `operation` - Operation type (for error events)
  - `reason` - Error reason (for error events)
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

  @doc """
  Emits a telemetry event for worker process start.
  """
  @spec emit_worker_start(term(), keyword()) :: :ok
  def emit_worker_start(worker_spec, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :worker_start],
      Map.new(measurements),
      %{worker_spec: inspect(worker_spec)}
    )
  end

  @doc """
  Emits a telemetry event for worker process termination.
  """
  @spec emit_worker_terminate(pid(), keyword()) :: :ok
  def emit_worker_terminate(pid, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :worker_terminate],
      Map.new(measurements),
      %{pid: pid}
    )
  end

  @doc """
  Emits a telemetry event for session process start.
  """
  @spec emit_session_start_event(String.t(), keyword()) :: :ok
  def emit_session_start_event(session_id, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :session_start],
      Map.new(measurements),
      %{session_id: session_id}
    )
  end

  @doc """
  Emits a telemetry event for session process end.
  """
  @spec emit_session_end_event(String.t(), keyword()) :: :ok
  def emit_session_end_event(session_id, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :session_end],
      Map.new(measurements),
      %{session_id: session_id}
    )
  end

  @doc """
  Emits a telemetry event for automatic session cleanup.
  """
  @spec emit_auto_cleanup_event(String.t(), atom(), pid(), keyword()) :: :ok
  def emit_auto_cleanup_event(session_id, module, pid, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :auto_cleanup],
      Map.new(measurements),
      %{session_id: session_id, module: module, pid: pid}
    )
  end

  @doc """
  Emits a telemetry event for rate limit check.
  """
  @spec emit_rate_limit_check(non_neg_integer(), non_neg_integer(), keyword()) :: :ok
  def emit_rate_limit_check(current_count, rate_limit, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :rate_limit_check],
      Map.new(measurements),
      %{current_count: current_count, rate_limit: rate_limit}
    )
  end

  @doc """
  Emits a telemetry event when rate limit is exceeded.
  """
  @spec emit_rate_limit_exceeded(non_neg_integer(), non_neg_integer(), keyword()) :: :ok
  def emit_rate_limit_exceeded(current_count, rate_limit, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :rate_limit_exceeded],
      Map.new(measurements),
      %{current_count: current_count, rate_limit: rate_limit}
    )
  end

  # Redux Telemetry Events

  @doc """
  Emits a telemetry event for Redux action dispatch.
  """
  @spec emit_redux_dispatch(String.t() | nil, any(), keyword()) :: :ok
  def emit_redux_dispatch(session_id, action, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :redux, :dispatch],
      Map.new(measurements),
      %{session_id: session_id, action: action}
    )
  end

  @doc """
  Emits a telemetry event for Redux subscription creation.
  """
  @spec emit_redux_subscribe(String.t() | nil, reference(), keyword()) :: :ok
  def emit_redux_subscribe(session_id, subscription_id, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :redux, :subscribe],
      Map.new(measurements),
      %{session_id: session_id, subscription_id: subscription_id}
    )
  end

  @doc """
  Emits a telemetry event for Redux subscription removal.
  """
  @spec emit_redux_unsubscribe(String.t() | nil, reference(), keyword()) :: :ok
  def emit_redux_unsubscribe(session_id, subscription_id, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :redux, :unsubscribe],
      Map.new(measurements),
      %{session_id: session_id, subscription_id: subscription_id}
    )
  end

  @doc """
  Emits a telemetry event for Redux subscription notification.
  """
  @spec emit_redux_notification(String.t() | nil, non_neg_integer(), keyword()) :: :ok
  def emit_redux_notification(session_id, subscription_count, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :redux, :notification],
      Map.new(measurements),
      %{session_id: session_id, subscription_count: subscription_count}
    )
  end

  @doc """
  Emits a telemetry event for Redux selector cache hit.
  """
  @spec emit_redux_selector_cache_hit(reference(), keyword()) :: :ok
  def emit_redux_selector_cache_hit(cache_key, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :redux, :selector_cache_hit],
      Map.new(measurements),
      %{cache_key: cache_key}
    )
  end

  @doc """
  Emits a telemetry event for Redux selector cache miss.
  """
  @spec emit_redux_selector_cache_miss(reference(), keyword()) :: :ok
  def emit_redux_selector_cache_miss(cache_key, measurements \\ []) do
    :telemetry.execute(
      [:phoenix, :session_process, :redux, :selector_cache_miss],
      Map.new(measurements),
      %{cache_key: cache_key}
    )
  end
end
