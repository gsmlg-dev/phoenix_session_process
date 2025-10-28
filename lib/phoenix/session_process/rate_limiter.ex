defmodule Phoenix.SessionProcess.RateLimiter do
  @moduledoc """
  Rate limiter for session creation using sliding window algorithm.

  This GenServer maintains an ETS table to track session creation timestamps
  and enforces the configured rate limit (sessions per minute).

  ## Configuration

      config :phoenix_session_process,
        rate_limit: 100  # Maximum 100 sessions per minute

  ## Algorithm

  Uses a sliding window approach:
  1. Stores timestamp for each session creation attempt
  2. Counts entries in the last 60 seconds
  3. Rejects new sessions if count >= rate_limit
  4. Automatically cleans up old entries every 10 seconds

  ## Performance

  - O(1) insertion with ETS
  - O(n) counting but optimized with select_count
  - Minimal memory overhead (only timestamps)
  - Thread-safe with ETS public table

  ## Telemetry

  Emits the following events:
  - `[:phoenix, :session_process, :rate_limit_exceeded]` - When limit is hit
  - `[:phoenix, :session_process, :rate_limit_check]` - On each check
  """
  use GenServer
  require Logger

  alias Phoenix.SessionProcess.{Config, Telemetry}

  @table_name :session_rate_limiter
  @window_size_ms 60_000
  @cleanup_interval_ms 10_000

  @doc """
  Starts the rate limiter GenServer.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Checks if a new session can be created under the current rate limit.

  Returns `:ok` if the session can be created, or `{:error, :rate_limit_exceeded}`
  if the rate limit would be exceeded.

  ## Examples

      iex> RateLimiter.check_rate_limit()
      :ok

      # After 100 requests in 1 minute
      iex> RateLimiter.check_rate_limit()
      {:error, :rate_limit_exceeded}
  """
  @spec check_rate_limit() :: :ok | {:error, :rate_limit_exceeded}
  def check_rate_limit do
    GenServer.call(__MODULE__, :check_rate_limit)
  end

  @doc """
  Gets the current request count in the sliding window.
  Useful for monitoring and debugging.

  ## Examples

      iex> RateLimiter.current_count()
      42
  """
  @spec current_count() :: non_neg_integer()
  def current_count do
    GenServer.call(__MODULE__, :current_count)
  end

  @doc """
  Resets the rate limiter by clearing all tracked requests.
  Useful for testing.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  ## Server Callbacks

  @impl true
  def init(_) do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:check_rate_limit, _from, state) do
    start_time = System.monotonic_time()
    now = System.system_time(:millisecond)
    rate_limit = Config.rate_limit()
    window_start = now - @window_size_ms

    # Count sessions created in the last minute
    recent_count =
      :ets.select_count(@table_name, [
        {{:_, :"$1"}, [{:>=, :"$1", window_start}], [true]}
      ])

    duration = System.monotonic_time() - start_time

    Telemetry.emit_rate_limit_check(recent_count, rate_limit, duration: duration)

    result =
      if recent_count < rate_limit do
        # Record this creation
        :ets.insert(@table_name, {make_ref(), now})
        :ok
      else
        Telemetry.emit_rate_limit_exceeded(recent_count, rate_limit, duration: duration)
        {:error, :rate_limit_exceeded}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:current_count, _from, state) do
    now = System.system_time(:millisecond)
    window_start = now - @window_size_ms

    count =
      :ets.select_count(@table_name, [
        {{:_, :"$1"}, [{:>=, :"$1", window_start}], [true]}
      ])

    {:reply, count, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_old_entries do
    now = System.system_time(:millisecond)
    window_start = now - @window_size_ms

    # Delete entries older than the sliding window
    deleted_count =
      :ets.select_delete(@table_name, [
        {{:_, :"$1"}, [{:<, :"$1", window_start}], [true]}
      ])

    if deleted_count > 0 do
      Logger.debug("RateLimiter: Cleaned up #{deleted_count} old entries")
    end

    :ok
  end
end
