defmodule Phoenix.SessionProcess.TelemetryLogger do
  @moduledoc """
  Default telemetry event logger for Phoenix.SessionProcess.

  This module provides handlers that can be attached to telemetry events
  to replicate the original Logger behavior while maintaining the benefits
  of telemetry-based observability.

  ## Usage

  Attach the default logger to capture all session process events:

      Phoenix.SessionProcess.TelemetryLogger.attach_default_logger()

  You can also attach individual event handlers:

      Phoenix.SessionProcess.TelemetryLogger.attach_worker_events()
      Phoenix.SessionProcess.TelemetryLogger.attach_session_events()
      Phoenix.SessionProcess.TelemetryLogger.attach_cleanup_events()

  ## Event Filtering

  You can filter events by log level:

      # Only log errors and warnings
      Phoenix.SessionProcess.TelemetryLogger.attach_default_logger(level: :warn)

      # Only log session lifecycle events
      Phoenix.SessionProcess.TelemetryLogger.attach_session_events(level: :info)

  ## Custom Handlers

  For custom logging behavior, you can attach your own handlers:

      :telemetry.attach_many("custom-logger", [
        [:phoenix, :session_process, :start],
        [:phoenix, :session_process, :stop]
      ], &MyApp.SessionLogger.handle_event/4, nil)
  """

  @type level :: :debug | :info | :warn | :error

  @doc """
  Attaches handlers for all Phoenix.SessionProcess telemetry events.
  """
  @spec attach_default_logger(keyword()) :: :ok
  def attach_default_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :info)

    :telemetry.attach_many("phoenix-session-process-default-logger", [
      [:phoenix, :session_process, :start],
      [:phoenix, :session_process, :stop],
      [:phoenix, :session_process, :start_error],
      [:phoenix, :session_process, :communication_error],
      [:phoenix, :session_process, :call],
      [:phoenix, :session_process, :cast],
      [:phoenix, :session_process, :auto_cleanup],
      [:phoenix, :session_process, :cleanup],
      [:phoenix, :session_process, :cleanup_error]
    ], fn _event, measurements, metadata ->
      handle_default_event(_event, measurements, metadata, level)
    end, %{level: level})
  end

  @doc """
  Attaches handlers for worker process events.
  """
  @spec attach_worker_events(keyword()) :: :ok
  def attach_worker_events(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)

    :telemetry.attach_many("phoenix-session-process-worker-logger", [
      [:phoenix, :session_process, :worker_start],
      [:phoenix, :session_process, :worker_terminate]
    ], fn _event, measurements, metadata ->
      handle_worker_event(_event, measurements, metadata, level)
    end, %{level: level})
  end

  @doc """
  Attaches handlers for session lifecycle events.
  """
  @spec attach_session_events(keyword()) :: :ok
  def attach_session_events(opts \\ []) do
    level = Keyword.get(opts, :level, :info)

    :telemetry.attach_many("phoenix-session-process-session-logger", [
      [:phoenix, :session_process, :start],
      [:phoenix, :session_process, :stop]
    ], fn _event, measurements, metadata ->
      handle_session_event(_event, measurements, metadata, level)
    end, %{level: level})
  end

  @doc """
  Attaches handlers for communication events.
  """
  @spec attach_communication_events(keyword()) :: :ok
  def attach_communication_events(opts \\ []) do
    level = Keyword.get(opts, :level, :info)

    :telemetry.attach_many("phoenix-session-process-communication-logger", [
      [:phoenix, :session_process, :start],
      [:phoenix, :session_process, :stop],
      [:phoenix, :session_process, :call],
      [:phoenix, :session_process, :cast],
      [:phoenix, :session_process, :start_error],
      [:phoenix, :session_process, :communication_error]
    ], fn _event, measurements, metadata ->
      handle_communication_event(_event, measurements, metadata, level)
    end, %{level: level})
  end

  @doc """
  Attaches handlers for cleanup events.
  """
  @spec attach_cleanup_events(keyword()) :: :ok
  def attach_cleanup_events(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)

    :telemetry.attach_many("phoenix-session-process-cleanup-logger", [
      [:phoenix, :session_process, :auto_cleanup],
      [:phoenix, :session_process, :cleanup],
      [:phoenix, :session_process, :cleanup_error]
    ], fn _event, measurements, metadata ->
      handle_cleanup_event(_event, measurements, metadata, level)
    end, %{level: level})
  end

  @doc """
  Detaches all telemetry logger handlers.
  """
  @spec detach_all_loggers() :: :ok
  def detach_all_loggers() do
    :telemetry.detach("phoenix-session-process-default-logger")
    :telemetry.detach("phoenix-session-process-worker-logger")
    :telemetry.detach("phoenix-session-process-session-logger")
    :telemetry.detach("phoenix-session-process-communication-logger")
    :telemetry.detach("phoenix-session-process-cleanup-logger")
  end

  # Private handler functions

  defp handle_default_event(_event, measurements, metadata, level) do
    if should_log?(level, metadata) do
      case _event do
        [:phoenix, :session_process, :start] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          Logger.info("Session #{session_id} started")

        [:phoenix, :session_process, :stop] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          Logger.info("Session #{session_id} stopped")

        [:phoenix, :session_process, :start_error] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          reason = Map.get(metadata, :reason, "unknown")
          Logger.error("Session start error #{session_id}: #{inspect(reason)}")

        [:phoenix, :session_process, :communication_error] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          reason = Map.get(metadata, :reason, "unknown")
          Logger.error("Session communication error #{session_id}: #{inspect(reason)}")

        [:phoenix, :session_process, :call] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          message = Map.get(metadata, :message, "unknown")
          Logger.info("Session call #{session_id}: #{inspect(message)}")

        [:phoenix, :session_process, :cast] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          message = Map.get(metadata, :message, "unknown")
          Logger.info("Session cast #{session_id}: #{inspect(message)}")

        [:phoenix, :session_process, :auto_cleanup] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          Logger.debug("Auto-cleanup expired session: #{session_id}")

        [:phoenix, :session_process, :cleanup] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          Logger.debug("Cleanup session: #{session_id}")

        [:phoenix, :session_process, :cleanup_error] ->
          session_id = Map.get(metadata, :session_id, "unknown")
          reason = Map.get(metadata, :reason, "unknown")
          Logger.error("Cleanup error #{session_id}: #{inspect(reason)}")

        _ ->
          :ok
      end
    end
  end

  defp handle_worker_event([:phoenix, :session_process, :worker_start], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      worker_spec = Map.get(metadata, :worker_spec, "unknown")
      Logger.debug("Worker start: #{worker_spec}")
    end
  end

  defp handle_worker_event([:phoenix, :session_process, :worker_terminate], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      pid = Map.get(metadata, :pid, "unknown")
      Logger.debug("Worker terminate: #{inspect(pid)}")
    end
  end

  defp handle_session_event([:phoenix, :session_process, :session_start], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      Logger.info("Session start: #{session_id}")
    end
  end

  defp handle_session_event([:phoenix, :session_process, :session_end], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      Logger.info("Session end: #{session_id}")
    end
  end

  defp handle_communication_event([:phoenix, :session_process, :call], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      message = Map.get(metadata, :message, "unknown")
      Logger.info("Session call #{session_id}: #{inspect(message)}")
    end
  end

  defp handle_communication_event([:phoenix, :session_process, :cast], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      message = Map.get(metadata, :message, "unknown")
      Logger.info("Session cast #{session_id}: #{inspect(message)}")
    end
  end

  defp handle_communication_event([:phoenix, :session_process, :start_error], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      reason = Map.get(metadata, :reason, "unknown")
      Logger.error("Session start error #{session_id}: #{inspect(reason)}")
    end
  end

  defp handle_communication_event([:phoenix, :session_process, :communication_error], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      reason = Map.get(metadata, :reason, "unknown")
      Logger.error("Session communication error #{session_id}: #{inspect(reason)}")
    end
  end

  defp handle_cleanup_event([:phoenix, :session_process, :auto_cleanup], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      Logger.debug("Auto-cleanup expired session: #{session_id}")
    end
  end

  defp handle_cleanup_event([:phoenix, :session_process, :cleanup], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      Logger.debug("Cleanup session: #{session_id}")
    end
  end

  defp handle_cleanup_event([:phoenix, :session_process, :cleanup_error], _measurements, metadata, level) do
    if should_log?(level, metadata) do
      session_id = Map.get(metadata, :session_id, "unknown")
      reason = Map.get(metadata, :reason, "unknown")
      Logger.error("Cleanup error #{session_id}: #{inspect(reason)}")
    end
  end

  defp should_log?(event_level, metadata) do
    configured_level = Application.get_env(:phoenix_session_process, :telemetry_log_level, :info)
    log_level_priority(configured_level) <= level_priority(:info)
  end

  defp level_priority(:debug), do: 0
  defp level_priority(:info), do: 1
  defp level_priority(:warn), do: 2
  defp level_priority(:error), do: 3
end