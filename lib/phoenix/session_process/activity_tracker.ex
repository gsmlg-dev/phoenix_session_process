defmodule Phoenix.SessionProcess.ActivityTracker do
  @moduledoc """
  Tracks session activity timestamps for TTL-based cleanup.

  This module maintains an ETS table that records the last activity time
  for each session. This enables intelligent cleanup that only removes
  truly idle sessions, not sessions that are actively being used.

  ## Usage

  The activity tracker is automatically initialized when the supervision tree starts.
  Activity is tracked automatically during session operations:

  - Session start: Initial activity recorded
  - Call operations: Activity updated
  - Cast operations: Activity updated
  - Manual touch: Activity updated via `touch/1`

  ## Cleanup Integration

  The Cleanup process uses this tracker to determine which sessions have
  expired based on inactivity rather than just creation time.

  ## Performance

  - ETS table with `:set` type for O(1) lookups
  - Public table for concurrent access
  - Read concurrency enabled for high-performance reads
  - Minimal memory overhead (only session_id + timestamp)

  ## Example

      # Touch a session to update its activity
      ActivityTracker.touch("session_123")

      # Get last activity time
      {:ok, timestamp} = ActivityTracker.get_last_activity("session_123")

      # Check if session is expired
      expired? = ActivityTracker.expired?("session_123", ttl: 3_600_000)
  """

  alias Phoenix.SessionProcess.Config

  @table_name :session_activity

  @doc """
  Initializes the activity tracker ETS table.
  This is called automatically during application startup.
  """
  @spec init() :: :ok
  def init do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

        :ok

      _ ->
        # Table already exists
        :ok
    end
  end

  @doc """
  Records or updates the last activity time for a session.

  ## Examples

      iex> ActivityTracker.touch("session_123")
      :ok
  """
  @spec touch(binary()) :: :ok
  def touch(session_id) do
    now = System.system_time(:millisecond)
    :ets.insert(@table_name, {session_id, now})
    :ok
  end

  @doc """
  Gets the last activity timestamp for a session.

  Returns `{:ok, timestamp}` if found, or `{:error, :not_found}` if the session
  has no recorded activity.

  ## Examples

      iex> ActivityTracker.touch("session_123")
      iex> ActivityTracker.get_last_activity("session_123")
      {:ok, 1234567890}

      iex> ActivityTracker.get_last_activity("nonexistent")
      {:error, :not_found}
  """
  @spec get_last_activity(binary()) :: {:ok, integer()} | {:error, :not_found}
  def get_last_activity(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, timestamp}] -> {:ok, timestamp}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Checks if a session has expired based on its last activity.

  A session is considered expired if:
  - It has no recorded activity (returns false - assume newly created)
  - Its last activity was more than TTL milliseconds ago (returns true)

  ## Options

  - `:ttl` - Time-to-live in milliseconds (defaults to configured session_ttl)

  ## Examples

      iex> ActivityTracker.touch("session_123")
      iex> ActivityTracker.expired?("session_123", ttl: 3_600_000)
      false

      # After 2 hours
      iex> ActivityTracker.expired?("session_123", ttl: 3_600_000)
      true
  """
  @spec expired?(binary(), keyword()) :: boolean()
  def expired?(session_id, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, Config.session_ttl())
    now = System.system_time(:millisecond)
    expiry_threshold = now - ttl

    case get_last_activity(session_id) do
      {:ok, last_activity} ->
        last_activity < expiry_threshold

      {:error, :not_found} ->
        # No activity recorded - assume newly created, not expired
        false
    end
  end

  @doc """
  Removes activity tracking for a session.
  Called automatically when a session terminates.

  ## Examples

      iex> ActivityTracker.remove("session_123")
      :ok
  """
  @spec remove(binary()) :: :ok
  def remove(session_id) do
    :ets.delete(@table_name, session_id)
    :ok
  end

  @doc """
  Gets all sessions that have expired.

  Returns a list of session IDs that haven't been active within the TTL window.

  ## Options

  - `:ttl` - Time-to-live in milliseconds (defaults to configured session_ttl)

  ## Examples

      iex> expired_sessions = ActivityTracker.get_expired_sessions(ttl: 3_600_000)
      ["session_1", "session_2"]
  """
  @spec get_expired_sessions(keyword()) :: [binary()]
  def get_expired_sessions(opts \\ []) do
    ttl = Keyword.get(opts, :ttl, Config.session_ttl())
    now = System.system_time(:millisecond)
    expiry_threshold = now - ttl

    # Get all sessions with last_activity < expiry_threshold
    :ets.select(@table_name, [
      {{:"$1", :"$2"}, [{:<, :"$2", expiry_threshold}], [:"$1"]}
    ])
  end

  @doc """
  Returns the total number of tracked sessions.

  ## Examples

      iex> ActivityTracker.count()
      42
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table_name, :size)
  end

  @doc """
  Removes all activity tracking data.
  Useful for testing.

  ## Examples

      iex> ActivityTracker.clear()
      :ok
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end
end
