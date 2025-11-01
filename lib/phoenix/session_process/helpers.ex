defmodule Phoenix.SessionProcess.Helpers do
  @moduledoc """
  Helper functions for common session management tasks.

  This module provides convenient functions for batch operations,
  session health checks, and common patterns.
  """

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.Config
  alias Phoenix.SessionProcess.Registry, as: SessionRegistry

  @doc """
  Start sessions for multiple session IDs in parallel.

  ## Examples

      iex> Phoenix.SessionProcess.Helpers.start_sessions(["session1", "session2"])
      [{"session1", {:ok, #PID<0.123.0>}}, {"session2", {:ok, #PID<0.124.0>}}]
  """
  @spec start_sessions([binary()]) :: [{binary(), {:ok, pid()} | {:error, term()}}]
  def start_sessions(session_ids) when is_list(session_ids) do
    session_ids
    |> Enum.map(fn session_id ->
      Task.async(fn -> {session_id, SessionProcess.start_session(session_id)} end)
    end)
    |> Task.await_many(5_000)
  end

  @doc """
  Terminate multiple sessions in parallel.

  ## Examples

      iex> Phoenix.SessionProcess.Helpers.terminate_sessions(["session1", "session2"])
      [{"session1", :ok}, {"session2", {:error, :not_found}}]
  """
  @spec terminate_sessions([binary()]) :: [{binary(), :ok | {:error, term()}}]
  def terminate_sessions(session_ids) when is_list(session_ids) do
    session_ids
    |> Enum.map(fn session_id ->
      Task.async(fn -> {session_id, SessionProcess.terminate(session_id)} end)
    end)
    |> Task.await_many(5_000)
  end

  @doc """
  Broadcast a message to all active sessions.

  ## Examples

      iex> Phoenix.SessionProcess.Helpers.broadcast_all({:system_message, "Maintenance in 5 minutes"})
      :ok
  """
  @spec broadcast_all(any()) :: :ok
  def broadcast_all(message) do
    SessionProcess.list_session()
    |> Enum.each(fn {session_id, _pid} ->
      SessionProcess.cast(session_id, message)
    end)

    :ok
  end

  @doc """
  Get health status for all sessions.

  ## Examples

      iex> Phoenix.SessionProcess.Helpers.session_health()
      %{healthy: 10, crashed: 0, total: 10}
  """
  @spec session_health :: %{healthy: integer(), crashed: integer(), total: integer()}
  def session_health do
    sessions = SessionProcess.list_session()

    {healthy, crashed} =
      sessions
      |> Enum.reduce({0, 0}, fn {_session_id, pid}, {h, c} ->
        case Process.alive?(pid) do
          true -> {h + 1, c}
          false -> {h, c + 1}
        end
      end)

    %{
      healthy: healthy,
      crashed: crashed,
      total: length(sessions)
    }
  end

  @doc """
  Find sessions by pattern matching on session ID.

  ## Examples

      iex> Phoenix.SessionProcess.Helpers.find_sessions_by_pattern(~r/user_.*/)
      ["user_123", "user_456"]
  """
  @spec find_sessions_by_pattern(Regex.t()) :: [binary()]
  def find_sessions_by_pattern(pattern) when is_struct(pattern, Regex) do
    SessionProcess.list_session()
    |> Enum.map(fn {session_id, _pid} -> session_id end)
    |> Enum.filter(fn session_id -> String.match?(session_id, pattern) end)
  end

  @doc """
  Safely call a session with automatic retry on timeout.

  ## Examples

      iex> Phoenix.SessionProcess.Helpers.safe_call("session_123", :get_user, 3)
      {:ok, %User{}}
  """
  @spec safe_call(binary(), any(), integer(), non_neg_integer()) ::
          {:ok, any()} | {:error, term()}
  def safe_call(session_id, request, retries \\ 3, timeout \\ 5_000) do
    do_safe_call(session_id, request, retries, timeout)
  end

  defp do_safe_call(_session_id, _request, 0, _timeout) do
    {:error, :max_retries_exceeded}
  end

  defp do_safe_call(session_id, request, retries, timeout) do
    case SessionProcess.call(session_id, request, timeout) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:timeout, _}} ->
        Process.sleep(100)
        do_safe_call(session_id, request, retries - 1, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a session with automatic retry on rate limit.

  ## Examples

      iex> Phoenix.SessionProcess.Helpers.create_session_with_retry("session_123")
      {:ok, #PID<0.123.0>}
  """
  @spec create_session_with_retry(binary(), module() | nil, any() | nil, integer()) ::
          {:ok, pid()} | {:error, term()}
  def create_session_with_retry(session_id, module \\ nil, arg \\ nil, retries \\ 5) do
    do_create_session_with_retry(session_id, module, arg, retries)
  end

  defp do_create_session_with_retry(_session_id, _module, _arg, 0) do
    {:error, :max_retries_exceeded}
  end

  defp do_create_session_with_retry(session_id, module, arg, retries) do
    # Build options for start_session/2
    opts =
      []
      |> Keyword.put_new_lazy(:module, fn -> module end)
      |> Keyword.put_new_lazy(:args, fn -> arg end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    result =
      if opts == [] do
        SessionProcess.start_session(session_id)
      else
        SessionProcess.start_session(session_id, opts)
      end

    case result do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:session_limit_reached, _max}} ->
        Process.sleep(200)
        do_create_session_with_retry(session_id, module, arg, retries - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the session module for a given process PID.
  """
  @spec get_session_module(pid()) :: module()
  def get_session_module(pid) do
    case Registry.lookup(SessionRegistry, pid) do
      [{_, module}] -> module
      _ -> Config.session_process()
    end
  end
end
