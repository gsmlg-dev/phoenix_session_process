# Dispatch Performance Benchmark
# Run with: mix run bench/dispatch_benchmark.exs
#
# This benchmark tests the dispatch performance of the Redux Store API:
# - Synchronous dispatch throughput
# - Async dispatch throughput
# - Dispatch with state updates
# - Concurrent dispatch operations
# - Subscription notification performance

IO.puts("🚀 Phoenix Session Process - Dispatch Performance Benchmark")
IO.puts(String.duplicate("=", 60))

# Start supervisor
{:ok, _} = Phoenix.SessionProcess.Supervisor.start_link([])

# Define a simple reducer for benchmarking
defmodule BenchReducer do
  use Phoenix.SessionProcess, :reducer

  @name :bench
  @action_prefix "bench"

  def init_state do
    %{counter: 0, updates: 0}
  end

  def handle_action(action, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "bench.increment"} ->
        %{state | counter: state.counter + 1, updates: state.updates + 1}

      %Action{type: "bench.set", payload: value} ->
        %{state | counter: value, updates: state.updates + 1}

      %Action{type: "bench.noop"} ->
        state

      _ ->
        state
    end
  end

  def handle_async(action, dispatch, _state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "bench.async_increment"} ->
        Task.async(fn ->
          dispatch.("bench.increment")
        end)

        fn -> :ok end

      _ ->
        fn -> nil end
    end
  end
end

defmodule BenchSession do
  use Phoenix.SessionProcess, :process

  def init_state(_arg) do
    %{}
  end

  def combined_reducers do
    [BenchReducer]
  end
end

# Create test session
session_id = "bench_session_#{:rand.uniform(1_000_000)}"
{:ok, _pid} = Phoenix.SessionProcess.start(session_id, BenchSession)

IO.puts("Session started: #{session_id}\n")

# Benchmark 1: Synchronous Dispatch Throughput
IO.puts("📊 1. Synchronous Dispatch Throughput")
IO.puts(String.duplicate("-", 40))

iterations = [100, 500, 1000, 5000]

Enum.each(iterations, fn count ->
  {time, _} =
    :timer.tc(fn ->
      Enum.each(1..count, fn _ ->
        :ok = Phoenix.SessionProcess.dispatch(session_id, "bench.increment")
      end)

      # Allow dispatches to complete
      Process.sleep(10)
    end)

  rate = Float.round(count / (time / 1_000_000), 2)
  avg_time = Float.round(time / count / 1000, 3)

  IO.puts(
    "  #{String.pad_leading(to_string(count), 5)} dispatches: #{String.pad_leading(Float.to_string(rate), 10)} ops/sec  (avg: #{avg_time}ms/op)"
  )
end)

# Reset state
:ok = Phoenix.SessionProcess.dispatch(session_id, "bench.set", 0)
Process.sleep(10)

# Benchmark 2: Async Dispatch with Cancellation
IO.puts("\n📊 2. Async Dispatch with Cancellation")
IO.puts(String.duplicate("-", 40))

Enum.each([100, 500, 1000], fn count ->
  {time, results} =
    :timer.tc(fn ->
      Enum.map(1..count, fn _ ->
        Phoenix.SessionProcess.dispatch_async(session_id, "bench.increment", nil, async: true)
      end)
    end)

  success_count =
    Enum.count(results, fn
      {:ok, _cancel_fn} -> true
      _ -> false
    end)

  rate = Float.round(success_count / (time / 1_000_000), 2)
  avg_time = Float.round(time / count / 1000, 3)

  IO.puts(
    "  #{String.pad_leading(to_string(count), 5)} async dispatches: #{String.pad_leading(Float.to_string(rate), 10)} ops/sec  (avg: #{avg_time}ms/op)"
  )

  # Allow async tasks to complete
  Process.sleep(50)
end)

# Reset state
:ok = Phoenix.SessionProcess.dispatch(session_id, "bench.set", 0)
Process.sleep(10)

# Benchmark 3: Concurrent Dispatch Operations
IO.puts("\n📊 3. Concurrent Dispatch Operations")
IO.puts(String.duplicate("-", 40))

concurrent_tasks = [10, 50, 100]

Enum.each(concurrent_tasks, fn task_count ->
  dispatches_per_task = 100
  total_dispatches = task_count * dispatches_per_task

  {time, _} =
    :timer.tc(fn ->
      tasks =
        Enum.map(1..task_count, fn _ ->
          Task.async(fn ->
            Enum.each(1..dispatches_per_task, fn _ ->
              :ok = Phoenix.SessionProcess.dispatch(session_id, "bench.increment")
            end)
          end)
        end)

      Task.await_many(tasks, 30_000)
      # Allow all dispatches to complete
      Process.sleep(50)
    end)

  rate = Float.round(total_dispatches / (time / 1_000_000), 2)

  IO.puts(
    "  #{String.pad_leading(to_string(task_count), 3)} tasks × #{dispatches_per_task} dispatches: #{String.pad_leading(Float.to_string(rate), 10)} ops/sec"
  )
end)

# Verify final count
state = Phoenix.SessionProcess.get_state(session_id)
IO.puts("\n  Final counter: #{state.bench.counter}")
IO.puts("  Total updates: #{state.bench.updates}")

# Reset state
:ok = Phoenix.SessionProcess.dispatch(session_id, "bench.set", 0)
Process.sleep(10)

# Benchmark 4: Dispatch with Subscriptions
IO.puts("\n📊 4. Dispatch with Active Subscriptions")
IO.puts(String.duplicate("-", 40))

# Create multiple subscriptions
subscription_counts = [1, 5, 10]

Enum.each(subscription_counts, fn sub_count ->
  # Subscribe multiple times
  sub_ids =
    Enum.map(1..sub_count, fn i ->
      event_name = :"counter_changed_#{i}"

      {:ok, sub_id} =
        Phoenix.SessionProcess.subscribe(
          session_id,
          fn state -> state.bench.counter end,
          event_name
        )

      # Clear initial notification
      receive do
        {^event_name, _} -> :ok
      after
        100 -> :ok
      end

      sub_id
    end)

  # Benchmark dispatches with subscriptions
  dispatch_count = 100

  {time, _} =
    :timer.tc(fn ->
      Enum.each(1..dispatch_count, fn _ ->
        :ok = Phoenix.SessionProcess.dispatch(session_id, "bench.increment")
      end)

      # Allow notifications to be sent
      Process.sleep(50)
    end)

  rate = Float.round(dispatch_count / (time / 1_000_000), 2)

  IO.puts(
    "  #{String.pad_leading(to_string(sub_count), 2)} subscriptions: #{String.pad_leading(Float.to_string(rate), 10)} ops/sec"
  )

  # Clear notification queue
  :timer.sleep(10)

  # Flush any remaining messages
  (fn flush ->
     receive do
       _ -> flush.(flush)
     after
       0 -> :ok
     end
   end).(fn f ->
    receive do
      _ -> f.(f)
    after
      0 -> :ok
    end
  end)

  # Unsubscribe
  Enum.each(sub_ids, fn sub_id ->
    :ok = Phoenix.SessionProcess.unsubscribe(session_id, sub_id)
  end)

  # Reset for next iteration
  :ok = Phoenix.SessionProcess.dispatch(session_id, "bench.set", 0)
  Process.sleep(10)
end)

# Benchmark 5: Different Action Types Performance
IO.puts("\n📊 5. Action Type Performance Comparison")
IO.puts(String.duplicate("-", 40))

action_types = [
  {"No-op (no state change)", "bench.noop"},
  {"Increment (state change)", "bench.increment"},
  {"Set value (state change)", "bench.set", 42}
]

Enum.each(action_types, fn
  {label, action_type} ->
    count = 1000

    {time, _} =
      :timer.tc(fn ->
        Enum.each(1..count, fn _ ->
          :ok = Phoenix.SessionProcess.dispatch(session_id, action_type)
        end)

        Process.sleep(10)
      end)

    rate = Float.round(count / (time / 1_000_000), 2)

    IO.puts(
      "  #{String.pad_trailing(label, 30)}: #{String.pad_leading(Float.to_string(rate), 10)} ops/sec"
    )

  {label, action_type, payload} ->
    count = 1000

    {time, _} =
      :timer.tc(fn ->
        Enum.each(1..count, fn _ ->
          :ok = Phoenix.SessionProcess.dispatch(session_id, action_type, payload)
        end)

        Process.sleep(10)
      end)

    rate = Float.round(count / (time / 1_000_000), 2)

    IO.puts(
      "  #{String.pad_trailing(label, 30)}: #{String.pad_leading(Float.to_string(rate), 10)} ops/sec"
    )
end)

# Benchmark 6: State Selector Performance
IO.puts("\n📊 6. State Selector Performance")
IO.puts(String.duplicate("-", 40))

# Set up state
:ok = Phoenix.SessionProcess.dispatch(session_id, "bench.set", 1000)
Process.sleep(10)

selectors = [
  {"Simple field access", fn s -> s.bench.counter end},
  {"Computed value", fn s -> s.bench.counter * 2 end},
  {"Conditional logic", fn s -> if s.bench.counter > 500, do: :high, else: :low end}
]

Enum.each(selectors, fn {label, selector} ->
  count = 10000

  # Client-side selection
  {time, _} =
    :timer.tc(fn ->
      Enum.each(1..count, fn _ ->
        _result = Phoenix.SessionProcess.get_state(session_id, selector)
      end)
    end)

  rate = Float.round(count / (time / 1_000_000), 2)

  IO.puts(
    "  #{String.pad_trailing(label <> " (client)", 35)}: #{String.pad_leading(Float.to_string(rate), 10)} ops/sec"
  )

  # Server-side selection
  {time2, _} =
    :timer.tc(fn ->
      Enum.each(1..count, fn _ ->
        _result = Phoenix.SessionProcess.select_state(session_id, selector)
      end)
    end)

  rate2 = Float.round(count / (time2 / 1_000_000), 2)

  IO.puts(
    "  #{String.pad_trailing(label <> " (server)", 35)}: #{String.pad_leading(Float.to_string(rate2), 10)} ops/sec"
  )
end)

# Summary
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("✅ Dispatch Benchmark Complete!")

final_state = Phoenix.SessionProcess.get_state(session_id)
IO.puts("\nFinal state:")
IO.puts("  Counter: #{final_state.bench.counter}")
IO.puts("  Total updates: #{final_state.bench.updates}")

# Cleanup
:ok = Phoenix.SessionProcess.terminate(session_id)
IO.puts("\n🧹 Cleaned up test session")
