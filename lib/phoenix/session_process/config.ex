defmodule Phoenix.SessionProcess.Config do
  @moduledoc """
  Configuration for Phoenix.SessionProcess.
  """

  @default_session_process Phoenix.SessionProcess.DefaultSessionProcess
  @default_max_sessions 10_000
  # 1 hour in milliseconds
  @default_session_ttl 3_600_000
  # sessions per minute
  @default_rate_limit 100

  @doc """
  Gets the configured session process module.
  """
  @spec session_process() :: module()
  def session_process() do
    Application.get_env(:phoenix_session_process, :session_process, @default_session_process)
  end

  @doc """
  Gets the maximum number of allowed concurrent sessions.
  """
  @spec max_sessions() :: integer()
  def max_sessions() do
    Application.get_env(:phoenix_session_process, :max_sessions, @default_max_sessions)
  end

  @doc """
  Gets the session TTL in milliseconds.
  """
  @spec session_ttl() :: integer()
  def session_ttl() do
    Application.get_env(:phoenix_session_process, :session_ttl, @default_session_ttl)
  end

  @doc """
  Gets the rate limit for session creation (sessions per minute).
  """
  @spec rate_limit() :: integer()
  def rate_limit() do
    Application.get_env(:phoenix_session_process, :rate_limit, @default_rate_limit)
  end

  @doc """
  Validates a session ID format.
  """
  @spec valid_session_id?(binary()) :: boolean()
  def valid_session_id?(session_id) do
    is_binary(session_id) and
      byte_size(session_id) > 0 and
      byte_size(session_id) <= 64 and
      String.match?(session_id, ~r/^[A-Za-z0-9_-]+$/)
  end
end
