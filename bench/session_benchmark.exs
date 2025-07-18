# Benchmarking script for Phoenix Session Process
# Run with: mix run bench/session_benchmark.exs
#
# This comprehensive benchmark tests all aspects of the Phoenix Session Process library:
# - Session creation and termination performance
# - Memory usage scaling
# - Concurrent operation handling
# - Registry lookup performance
# - Error handling performance
# - Helper function efficiency

alias Phoenix.SessionProcess
alias Phoenix.SessionProcess.Helpers

IO.puts("🚀 Phoenix Session Process Benchmarking")
IO.puts(String.duplicate("=", 50))

# Warm up the system
IO.puts("Warming up...")
for _i <- 1..100 do
  SessionProcess.start("warmup_#{System.unique_integer()}")
end

# Clear warmup sessions
Enum.each(SessionProcess.list_session(), fn {session_id, _pid} ->
  SessionProcess.terminate(session_id)
end)

IO.puts("Starting benchmarks...")

# Benchmark configurations
num_sessions = [100, 500, 1000]
concurrent_ops = [10, 50, 100]

# 1. Session Creation Performance
IO.puts("\n📊 Session Creation Benchmark")
IO.puts("-" * 30)

Enum.each(num_sessions, fn count ->
  {time, _} = :timer.tc(fn ->
    1..count
    |> Enum.map(&"session_#{&1}")
    |> Helpers.start_sessions()
  end)
  
  rate = Float.round(count / (time / 1_000_000), 2)
  IO.puts("Created #{count} sessions in #{time / 1_000}ms (#{rate} sessions/sec)")
end)

# Clear sessions
Enum.each(SessionProcess.list_session(), fn {session_id, _pid} ->
  SessionProcess.terminate(session_id)
end)

# 2. Session Communication Performance
IO.puts("\n📊 Session Communication Benchmark")
IO.puts("-" * 35)

# Create test sessions
Enum.each(1..100, fn i ->
  SessionProcess.start("comm_test_#{i}")
end)

# Benchmark calls vs casts
Enum.each(concurrent_ops, fn ops ->
  {call_time, _} = :timer.tc(fn ->
    1..ops
    |> Enum.map(fn i ->
      Task.async(fn ->
        SessionProcess.call("comm_test_#{i}", :ping)
      end)
    end)
    |> Task.await_many(5000)
  end)

  {cast_time, _} = :timer.tc(fn ->
    1..ops
    |> Enum.map(fn i ->
      Task.async(fn ->
        SessionProcess.cast("comm_test_#{i}", :ping)
      end)
    end)
    |> Task.await_many(5000)
  end)

  IO.puts("#{ops} concurrent calls: #{call_time / 1000}ms")
  IO.puts("#{ops} concurrent casts: #{cast_time / 1000}ms")
end)

# 3. Memory Usage Analysis
IO.puts("\n📊 Memory Usage Analysis")
IO.puts("-" * 25)

# Create varying session counts
memory_tests = [100, 500, 1000]

Enum.each(memory_tests, fn count ->
  # Clear existing sessions
  Enum.each(SessionProcess.list_session(), fn {session_id, _pid} ->
    SessionProcess.terminate(session_id)
  end)

  # Create sessions
  Enum.each(1..count, fn i ->
    SessionProcess.start("memory_test_#{i}")
  end)

  # Measure memory
  stats = SessionProcess.session_stats()
  memory_mb = stats.memory_usage / 1024 / 1024
  avg_memory_kb = stats.avg_memory_per_session / 1024

  IO.puts("#{count} sessions: #{Float.round(memory_mb, 2)}MB total, #{Float.round(avg_memory_kb, 2)}KB per session")
end)

# 4. Registry Lookup Performance
IO.puts("\n📊 Registry Lookup Performance")
IO.puts("-" * 32)

# Create sessions for lookup tests
Enum.each(1..1000, fn i ->
  SessionProcess.start("lookup_test_#{i}")
end)

lookup_tests = [100, 1000, 5000]

Enum.each(lookup_tests, fn iterations ->
  {time, _} = :timer.tc(fn ->
    Enum.each(1..iterations, fn i ->
      SessionProcess.started?("lookup_test_#{rem(i, 1000) + 1}")
    end)
  end)

  rate = Float.round(iterations / (time / 1_000_000), 0)
  IO.puts("#{iterations} registry lookups: #{time / 1000}ms (#{rate} lookups/sec)")
end)

# 5. Error Handling Performance
IO.puts("\n📊 Error Handling Performance")
IO.puts("-" * 30)

error_tests = [
  {:invalid_session_id, "invalid@session"},
  {:session_not_found, "nonexistent_session"},
  {:timeout_scenario, "timeout_test"}
]

Enum.each(error_tests, fn {scenario, test_id} ->
  {time, result} = :timer.tc(fn ->
    case scenario do
      :invalid_session_id ->
        SessionProcess.start(test_id)
      :session_not_found ->
        SessionProcess.call(test_id, :ping)
      :timeout_scenario ->
        SessionProcess.start(test_id)
        SessionProcess.call(test_id, :slow_operation, 1)
    end
  end)

  IO.puts("#{scenario}: #{time / 1000}ms - #{inspect(result)}")
end)

# 6. Cleanup Performance
IO.puts("\n📊 Cleanup Performance")
IO.puts("-" * 23)

session_count = length(SessionProcess.list_session())
{cleanup_time, _} = :timer.tc(fn ->
  Enum.each(SessionProcess.list_session(), fn {session_id, _pid} ->
    SessionProcess.terminate(session_id)
  end)
end)

cleanup_rate = Float.round(session_count / (cleanup_time / 1_000_000), 2)
IO.puts("Cleaned up #{session_count} sessions in #{cleanup_time / 1000}ms (#{cleanup_rate} sessions/sec)")

# 7. Helper Functions Performance
IO.puts("\n📊 Helper Functions Performance")
IO.puts("-" * 33)

# Test batch operations
Enum.each([100, 200], fn count ->
  session_ids = Enum.map(1..count, &"batch_test_#{&1}")
  
  {start_time, _} = :timer.tc(fn ->
    Helpers.start_sessions(session_ids)
  end)
  
  {terminate_time, _} = :timer.tc(fn ->
    Helpers.terminate_sessions(session_ids)
  end)

  IO.puts("#{count} sessions batch start: #{start_time / 1000}ms")
  IO.puts("#{count} sessions batch terminate: #{terminate_time / 1000}ms")
end)

# 8. Concurrent Stress Test
IO.puts("\n📊 Concurrent Stress Test")
IO.puts("-" * 27)

stress_test = fn concurrent_ops ->
  {time, results} = :timer.tc(fn ->
    1..concurrent_ops
    |> Enum.map(fn i ->
      Task.async(fn ->
        session_id = "stress_#{i}_#{System.unique_integer()}"
        case SessionProcess.start(session_id) do
          {:ok, _pid} ->
            SessionProcess.call(session_id, :ping)
            SessionProcess.terminate(session_id)
            :ok
          error -> error
        end
      end)
    end)
    |> Task.await_many(10000)
  end)

  success_count = Enum.count(results, &(&1 == :ok))
  rate = Float.round(concurrent_ops / (time / 1_000_000), 2)
  IO.puts("#{concurrent_ops} concurrent ops: #{time / 1000}ms (#{rate} ops/sec) - #{success_count}/#{concurrent_ops} successful")
end

stress_test.(100)
stress_test.(500)

IO.puts("\n✅ Benchmarking Complete!")
IO.puts(String.duplicate("=", 50))

# Final system stats
final_stats = SessionProcess.session_stats()
IO.puts("Final system state:")
IO.inspect(final_stats, label: "Session Stats")