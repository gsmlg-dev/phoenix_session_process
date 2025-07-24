# Simple benchmark for quick testing
# Run with: mix run bench/simple_bench.exs
#
# This benchmark provides a quick performance overview of the Phoenix Session Process library.
# It tests session creation, communication, memory usage, and cleanup in under 10 seconds.

alias Phoenix.SessionProcess
alias Phoenix.SessionProcess.Helpers

# Configure and start required processes
Application.put_env(:phoenix_session_process, :session_process, Phoenix.SessionProcess.DefaultSessionProcess)
{:ok, _} = Phoenix.SessionProcess.Supervisor.start_link([])

IO.puts("🔍 Simple Phoenix Session Process Benchmark")
IO.puts(String.duplicate("=", 45))

# Quick session creation test
IO.puts("\n1. Session Creation (100 sessions)")
{time, results} = :timer.tc(fn ->
  Enum.map(1..100, fn i ->
    SessionProcess.start("quick_test_#{i}")
  end)
end)

success_count = Enum.count(results, &match?({:ok, _}, &1))
IO.puts("Created #{success_count}/100 sessions in #{time / 1000}ms (#{Float.round(success_count / (time / 1_000_000), 2)} sessions/sec)")

# Quick communication test
IO.puts("\n2. Session Communication (50 calls)")
{call_time, call_results} = :timer.tc(fn ->
  1..50
  |> Enum.map(fn i ->
    Task.async(fn ->
      SessionProcess.call("quick_test_#{i}", :ping)
    end)
  end)
  |> Task.await_many(5000)
end)

call_success = Enum.count(call_results, &match?({:ok, _}, &1))
IO.puts("#{call_success}/50 calls completed in #{call_time / 1000}ms (#{Float.round(call_success / (call_time / 1_000_000), 2)} calls/sec)")

# Memory usage
stats = SessionProcess.session_stats()
IO.puts("\n3. Memory Usage")
IO.puts("Active sessions: #{stats.total_sessions}")
IO.puts("Total memory: #{Float.round(stats.memory_usage / 1024, 2)}KB")
IO.puts("Avg per session: #{Float.round(stats.avg_memory_per_session / 1024, 2)}KB")

# Cleanup
IO.puts("\n4. Cleanup Test")
{cleanup_time, _} = :timer.tc(fn ->
  Enum.each(1..100, fn i ->
    SessionProcess.terminate("quick_test_#{i}")
  end)
end)

IO.puts("Cleaned up 100 sessions in #{cleanup_time / 1000}ms")

IO.puts("\n✅ Quick benchmark complete!")