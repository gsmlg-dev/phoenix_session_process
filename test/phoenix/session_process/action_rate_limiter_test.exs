defmodule Phoenix.SessionProcess.ActionRateLimiterTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess.ActionRateLimiter

  describe "parse_duration/1" do
    test "parses milliseconds" do
      assert ActionRateLimiter.parse_duration("500ms") == 500
      assert ActionRateLimiter.parse_duration("1000ms") == 1000
    end

    test "parses seconds" do
      assert ActionRateLimiter.parse_duration("1s") == 1000
      assert ActionRateLimiter.parse_duration("5s") == 5000
    end

    test "parses minutes" do
      assert ActionRateLimiter.parse_duration("1m") == 60_000
      assert ActionRateLimiter.parse_duration("5m") == 300_000
    end

    test "parses hours" do
      assert ActionRateLimiter.parse_duration("1h") == 3_600_000
      assert ActionRateLimiter.parse_duration("2h") == 7_200_000
    end

    test "raises on invalid format" do
      assert_raise ArgumentError, ~r/Invalid duration format/, fn ->
        ActionRateLimiter.parse_duration("invalid")
      end

      assert_raise ArgumentError, ~r/Invalid duration format/, fn ->
        ActionRateLimiter.parse_duration("100")
      end

      assert_raise ArgumentError, ~r/Invalid duration format/, fn ->
        ActionRateLimiter.parse_duration("5x")
      end
    end
  end

  describe "should_throttle?/3" do
    defmodule TestThrottleModule do
      def __reducer_throttles__, do: [{"fetch-data", "1000ms"}]
      def __reducer_module__, do: true
    end

    defmodule NoThrottleModule do
      def __reducer_module__, do: true
    end

    test "returns false if module has no throttles" do
      state = %{_redux_throttle_state: %{}}
      action = %{type: "fetch-data"}

      refute ActionRateLimiter.should_throttle?(NoThrottleModule, action, state)
    end

    test "returns false on first call (no previous timestamp)" do
      state = %{_redux_throttle_state: %{}}
      action = %{type: "fetch-data"}

      refute ActionRateLimiter.should_throttle?(TestThrottleModule, action, state)
    end

    test "returns true if called within throttle duration" do
      now = System.monotonic_time(:millisecond)
      action = %{type: "fetch-data"}
      throttle_key = {TestThrottleModule, "fetch-data"}

      state = %{
        _redux_throttle_state: %{throttle_key => now}
      }

      assert ActionRateLimiter.should_throttle?(TestThrottleModule, action, state)
    end

    test "returns false if called after throttle duration has passed" do
      # 2 seconds ago (throttle is 1 second)
      past = System.monotonic_time(:millisecond) - 2000
      action = %{type: "fetch-data"}
      throttle_key = {TestThrottleModule, "fetch-data"}

      state = %{
        _redux_throttle_state: %{throttle_key => past}
      }

      refute ActionRateLimiter.should_throttle?(TestThrottleModule, action, state)
    end

    test "handles different action patterns" do
      state = %{_redux_throttle_state: %{}}

      # Atom action
      assert ActionRateLimiter.should_throttle?(TestThrottleModule, :other_action, state) ==
               false

      # Tuple action
      assert ActionRateLimiter.should_throttle?(
               TestThrottleModule,
               {:other_action, %{}},
               state
             ) == false
    end
  end

  describe "record_throttle/3" do
    defmodule RecordThrottleModule do
      def __reducer_throttles__, do: [{"fetch-data", "1000ms"}]
      def __reducer_module__, do: true
    end

    test "records timestamp for throttled actions" do
      state = %{_redux_throttle_state: %{}}
      action = %{type: "fetch-data"}

      new_state = ActionRateLimiter.record_throttle(RecordThrottleModule, action, state)

      throttle_key = {RecordThrottleModule, "fetch-data"}
      assert is_integer(new_state._redux_throttle_state[throttle_key])
    end

    test "doesn't modify state for non-throttled actions" do
      state = %{_redux_throttle_state: %{}}
      action = %{type: "other-action"}

      new_state = ActionRateLimiter.record_throttle(RecordThrottleModule, action, state)

      assert new_state == state
    end

    test "updates existing timestamp" do
      old_time = System.monotonic_time(:millisecond) - 5000
      throttle_key = {RecordThrottleModule, "fetch-data"}

      state = %{
        _redux_throttle_state: %{throttle_key => old_time}
      }

      action = %{type: "fetch-data"}
      new_state = ActionRateLimiter.record_throttle(RecordThrottleModule, action, state)

      # New timestamp should be greater than old one
      assert new_state._redux_throttle_state[throttle_key] > old_time
    end
  end

  describe "should_debounce?/2" do
    defmodule TestDebounceModule do
      def __reducer_debounces__, do: [{"search-query", "500ms"}]
      def __reducer_module__, do: true
    end

    defmodule NoDebounceModule do
      def __reducer_module__, do: true
    end

    test "returns true if action matches debounce config" do
      action = %{type: "search-query"}
      assert ActionRateLimiter.should_debounce?(TestDebounceModule, action)
    end

    test "returns false if action doesn't match" do
      action = %{type: "other-action"}
      refute ActionRateLimiter.should_debounce?(TestDebounceModule, action)
    end

    test "returns false if module has no debounces" do
      action = %{type: "any-action"}
      refute ActionRateLimiter.should_debounce?(NoDebounceModule, action)
    end
  end

  describe "schedule_debounce/4" do
    defmodule ScheduleDebounceModule do
      def __reducer_debounces__, do: [{"search-query", "100ms"}]
      def __reducer_module__, do: true
    end

    test "schedules a timer for debounced action" do
      state = %{_redux_debounce_timers: %{}}
      action = %{type: "search-query"}
      session_pid = self()

      new_state =
        ActionRateLimiter.schedule_debounce(ScheduleDebounceModule, action, session_pid, state)

      debounce_key = {ScheduleDebounceModule, "search-query"}
      assert is_reference(new_state._redux_debounce_timers[debounce_key])
    end

    test "cancels existing timer when scheduling new one" do
      action = %{type: "search-query"}
      session_pid = self()
      debounce_key = {ScheduleDebounceModule, "search-query"}

      # Create initial state with a timer
      state = %{_redux_debounce_timers: %{}}

      state1 =
        ActionRateLimiter.schedule_debounce(ScheduleDebounceModule, action, session_pid, state)

      timer_ref1 = state1._redux_debounce_timers[debounce_key]

      # Schedule again - should cancel first timer
      state2 =
        ActionRateLimiter.schedule_debounce(ScheduleDebounceModule, action, session_pid, state1)

      timer_ref2 = state2._redux_debounce_timers[debounce_key]

      # Should be different references
      assert timer_ref1 != timer_ref2
      assert is_reference(timer_ref2)
    end

    test "doesn't modify state for non-debounced actions" do
      state = %{_redux_debounce_timers: %{}}
      action = %{type: "other-action"}
      session_pid = self()

      new_state =
        ActionRateLimiter.schedule_debounce(ScheduleDebounceModule, action, session_pid, state)

      assert new_state == state
    end

    test "sends debounced action message after delay" do
      state = %{_redux_debounce_timers: %{}}
      action = %{type: "search-query", payload: "test"}
      session_pid = self()

      _new_state =
        ActionRateLimiter.schedule_debounce(ScheduleDebounceModule, action, session_pid, state)

      # Wait for timer (100ms + buffer)
      assert_receive {:debounced_action, ScheduleDebounceModule, ^action}, 200
    end
  end

  describe "cancel_all_debounce_timers/1" do
    defmodule CancelModule do
      def __reducer_debounces__, do: [{"action1", "100ms"}, {"action2", "100ms"}]
      def __reducer_module__, do: true
    end

    test "cancels all timers" do
      session_pid = self()
      state = %{_redux_debounce_timers: %{}}

      # Schedule multiple timers
      action1 = %{type: "action1"}
      action2 = %{type: "action2"}

      state1 = ActionRateLimiter.schedule_debounce(CancelModule, action1, session_pid, state)
      state2 = ActionRateLimiter.schedule_debounce(CancelModule, action2, session_pid, state1)

      # Verify timers are scheduled
      assert map_size(state2._redux_debounce_timers) == 2

      # Cancel all
      :ok = ActionRateLimiter.cancel_all_debounce_timers(state2)

      # Wait to ensure no messages arrive
      refute_receive {:debounced_action, _, _}, 200
    end

    test "handles empty timer map" do
      state = %{_redux_debounce_timers: %{}}
      assert :ok = ActionRateLimiter.cancel_all_debounce_timers(state)
    end
  end
end
