defmodule Phoenix.SessionProcess.Redux.ActionRateLimiter do
  @moduledoc """
  Rate limiting for Redux actions via throttle and debounce.

  ## Throttle

  Execute action immediately, then block subsequent calls for the specified duration.
  Useful for limiting API calls, preventing spam clicks, etc.

  ## Debounce

  Delay action execution until the specified duration has passed since the last call.
  Useful for search inputs, auto-save, etc.

  ## Duration Format

  Durations can be specified as strings:
  - `"500ms"` - 500 milliseconds
  - `"1s"` - 1 second
  - `"5m"` - 5 minutes
  - `"1h"` - 1 hour
  """

  @doc """
  Parse time string like "3000ms", "1s", "5m", "1h" to milliseconds.

  ## Examples

      iex> ActionRateLimiter.parse_duration("500ms")
      500

      iex> ActionRateLimiter.parse_duration("1s")
      1000

      iex> ActionRateLimiter.parse_duration("5m")
      300_000

      iex> ActionRateLimiter.parse_duration("1h")
      3_600_000
  """
  @spec parse_duration(String.t()) :: non_neg_integer()
  def parse_duration(duration) when is_binary(duration) do
    case Regex.run(~r/^(\d+)(ms|s|m|h)$/, duration) do
      [_, num, "ms"] ->
        String.to_integer(num)

      [_, num, "s"] ->
        String.to_integer(num) * 1000

      [_, num, "m"] ->
        String.to_integer(num) * 60_000

      [_, num, "h"] ->
        String.to_integer(num) * 3_600_000

      _ ->
        raise ArgumentError,
              "Invalid duration format: #{duration}. Expected format: <number><unit> where unit is ms, s, m, or h"
    end
  end

  @doc """
  Check if action should be throttled based on module's throttle configuration.

  Throttle: Execute immediately on first call, then block for duration.

  ## Parameters
  - `module` - The reducer module with `@throttle` attributes
  - `action` - The action to check
  - `state` - The session process state containing throttle tracking

  ## Returns
  - `true` if action should be blocked (throttled)
  - `false` if action should be allowed
  """
  @spec should_throttle?(module(), term(), map()) :: boolean()
  def should_throttle?(module, action, state) do
    throttles = get_module_throttles(module)
    action_pattern = get_action_pattern(action)

    case find_throttle_config(throttles, action_pattern) do
      nil ->
        false

      {_pattern, duration_str} ->
        duration_ms = parse_duration(duration_str)
        throttle_key = {module, action_pattern}
        last_time = get_in(state, [:_redux_throttle_state, throttle_key])

        if last_time do
          now = System.monotonic_time(:millisecond)
          elapsed = now - last_time
          elapsed < duration_ms
        else
          # First call - allow and will be recorded
          false
        end
    end
  end

  @doc """
  Record throttle execution timestamp.

  Should be called after an action is executed to record when it happened.

  ## Parameters
  - `module` - The reducer module
  - `action` - The action that was executed
  - `state` - The session process state

  ## Returns
  - Updated state with recorded timestamp
  """
  @spec record_throttle(module(), term(), map()) :: map()
  def record_throttle(module, action, state) do
    throttles = get_module_throttles(module)
    action_pattern = get_action_pattern(action)

    if find_throttle_config(throttles, action_pattern) do
      throttle_key = {module, action_pattern}
      now = System.monotonic_time(:millisecond)

      throttle_state = Map.get(state, :_redux_throttle_state, %{})
      new_throttle_state = Map.put(throttle_state, throttle_key, now)

      Map.put(state, :_redux_throttle_state, new_throttle_state)
    else
      state
    end
  end

  @doc """
  Check if action should be debounced based on module's debounce configuration.

  Debounce: Delay execution, reset timer on new call.

  ## Parameters
  - `module` - The reducer module with `@debounce` attributes
  - `action` - The action to check

  ## Returns
  - `true` if action should be debounced (delayed)
  - `false` if action should execute immediately
  """
  @spec should_debounce?(module(), term()) :: boolean()
  def should_debounce?(module, action) do
    debounces = get_module_debounces(module)
    action_pattern = get_action_pattern(action)

    find_debounce_config(debounces, action_pattern) != nil
  end

  @doc """
  Schedule debounced action execution.

  Cancels any existing timer for this action and schedules a new one.

  ## Parameters
  - `module` - The reducer module
  - `action` - The action to schedule
  - `session_pid` - The session process PID
  - `state` - The session process state

  ## Returns
  - Updated state with new debounce timer reference
  """
  @spec schedule_debounce(module(), term(), pid(), map()) :: map()
  def schedule_debounce(module, action, session_pid, state) do
    debounces = get_module_debounces(module)
    action_pattern = get_action_pattern(action)

    case find_debounce_config(debounces, action_pattern) do
      {_pattern, duration_str} ->
        duration_ms = parse_duration(duration_str)
        debounce_key = {module, action_pattern}

        # Cancel existing timer if any
        debounce_timers = Map.get(state, :_redux_debounce_timers, %{})

        if timer_ref = Map.get(debounce_timers, debounce_key) do
          Process.cancel_timer(timer_ref)
        end

        # Schedule new timer
        timer_ref =
          Process.send_after(
            session_pid,
            {:debounced_action, module, action},
            duration_ms
          )

        new_debounce_timers = Map.put(debounce_timers, debounce_key, timer_ref)
        Map.put(state, :_redux_debounce_timers, new_debounce_timers)

      nil ->
        state
    end
  end

  @doc """
  Cancel all debounce timers for cleanup.

  Should be called when session process terminates.

  ## Parameters
  - `state` - The session process state

  ## Returns
  - `:ok`
  """
  @spec cancel_all_debounce_timers(map()) :: :ok
  def cancel_all_debounce_timers(state) do
    debounce_timers = Map.get(state, :_redux_debounce_timers, %{})

    Enum.each(debounce_timers, fn {_key, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    :ok
  end

  # Private helpers

  defp get_module_throttles(module) do
    if function_exported?(module, :__reducer_throttles__, 0) do
      module.__reducer_throttles__()
    else
      []
    end
  end

  defp get_module_debounces(module) do
    if function_exported?(module, :__reducer_debounces__, 0) do
      module.__reducer_debounces__()
    else
      []
    end
  end

  defp find_throttle_config(throttles, action_pattern) do
    Enum.find(throttles, fn {pattern, _duration} ->
      pattern == action_pattern
    end)
  end

  defp find_debounce_config(debounces, action_pattern) do
    Enum.find(debounces, fn {pattern, _duration} ->
      pattern == action_pattern
    end)
  end

  defp get_action_pattern(%{type: type}), do: type
  defp get_action_pattern(action) when is_atom(action), do: action
  defp get_action_pattern({action, _}), do: action
  defp get_action_pattern(_), do: :unknown
end
