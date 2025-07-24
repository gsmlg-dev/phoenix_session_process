# Phoenix Session Process Benchmarking Guide

This directory contains comprehensive benchmarking tools to measure the performance of the Phoenix Session Process library.

## Overview

The benchmarking suite provides tools to measure:
- Session creation and termination performance
- Memory usage and efficiency
- Concurrent operation throughput
- Registry lookup performance
- Error handling performance

## Files

- **`simple_bench.exs`** - Quick performance test (5-10 seconds)
- **`session_benchmark.exs`** - Comprehensive benchmark (30-60 seconds)
- **`README.md`** - This documentation

## Usage

### Quick Benchmark
Run a fast performance check:

```bash
mix run bench/simple_bench.exs
```

**Sample Output:**
```
🔍 Simple Phoenix Session Process Benchmark
=============================================

1. Session Creation (100 sessions)
Created 100/100 sessions in 8.959ms (11161.96 sessions/sec)

2. Session Communication (50 calls)
50/50 calls completed in 0.297ms (168.35 calls/sec)

3. Memory Usage
Active sessions: 100
Total memory: 1024.0KB
Avg per session: 10.24KB

4. Cleanup Test
Cleaned up 100 sessions in 4.496ms

✅ Quick benchmark complete!
```

### Comprehensive Benchmark
Run detailed performance analysis:

```bash
mix run bench/session_benchmark.exs
```

**Sample Output:**
```
🚀 Phoenix Session Process Benchmarking
==================================================

📊 Session Creation Benchmark
------------------------------
Created 100 sessions in 8.9ms (11235.96 sessions/sec)
Created 500 sessions in 45.2ms (11061.95 sessions/sec)
Created 1000 sessions in 89.7ms (11148.27 sessions/sec)

📊 Session Communication Benchmark
-----------------------------------
10 concurrent calls: 1.2ms (8333.33 calls/sec)
50 concurrent calls: 5.8ms (8620.69 calls/sec)
100 concurrent calls: 11.4ms (8771.93 calls/sec)

📊 Memory Usage Analysis
------------------------
100 sessions: 1.02MB total, 10.5KB per session
500 sessions: 5.12MB total, 10.5KB per session
1000 sessions: 10.24MB total, 10.5KB per session

📊 Registry Lookup Performance
-------------------------------
100 registry lookups: 0.8ms (125000 lookups/sec)
1000 registry lookups: 7.9ms (126582 lookups/sec)
5000 registry lookups: 39.2ms (127551 lookups/sec)

📊 Helper Functions Performance
--------------------------------
100 sessions batch start: 12.3ms
100 sessions batch terminate: 8.7ms

✅ Benchmarking Complete!
```

## Benchmark Metrics Explained

### Performance Indicators
- **Sessions/sec**: Rate of session creation/termination
- **Calls/sec**: Rate of GenServer calls/casts
- **Memory/session**: Average memory usage per session
- **Latency**: Time for individual operations

### What to Look For
- **Good Performance**: 
  - >10,000 sessions/sec creation rate
  - <1ms latency for registry lookups
  - Linear memory scaling
- **Warning Signs**:
  - <1,000 sessions/sec
  - Memory usage >100KB per empty session
  - Non-linear scaling patterns

## Integration Testing

### In Your Application
To benchmark your own Phoenix app:

```elixir
# In your test environment
Application.put_env(:my_app, :session_process, MyApp.SessionProcess)
{:ok, _} = Phoenix.SessionProcess.Supervisor.start_link([])

# Run benchmarks
bench_results = BenchHelper.run_session_benchmark()
```

### Custom Benchmarks
Create custom benchmarks for your specific use case:

```elixir
# Custom session creation benchmark
defmodule MyApp.Bench do
  def custom_bench do
    sessions = Enum.map(1..1000, &"user_#{&1}")
    
    {time, _} = :timer.tc(fn ->
      Phoenix.SessionProcess.Helpers.start_sessions(sessions)
    end)
    
    rate = 1000 / (time / 1_000_000)
    IO.puts("Custom rate: #{rate} sessions/sec")
  end
end
```

## Performance Tuning

Based on benchmark results, you can optimize:

1. **Session TTL**: Adjust based on memory usage
2. **Max Sessions**: Set based on creation rate and memory capacity
3. **Registry Size**: Monitor lookup performance
4. **Process Limits**: Ensure adequate system resources

## Troubleshooting

### Common Issues
- **Registry not found**: Ensure supervisor is started
- **Memory spikes**: Check for session leaks
- **Slow creation**: Verify system resources

### Debug Commands
```bash
# Check active sessions
iex -S mix
Phoenix.SessionProcess.session_info()
Phoenix.SessionProcess.session_stats()
```

## Continuous Monitoring

For production monitoring, use the telemetry events:

```elixir
# Track session lifecycle
:telemetry.attach_many("session-metrics", [
  [:phoenix, :session_process, :start],
  [:phoenix, :session_process, :stop],
  [:phoenix, :session_process, :call]
], fn event, measurements, _meta, _config ->
  IO.inspect({event, measurements})
end, nil)
```

## Environment Setup

### Requirements
- Elixir 1.12+
- Erlang/OTP 24+
- Phoenix Session Process library

### Dependencies
Add to `mix.exs` for development:

```elixir
defp deps do
  [
    {:benchee, "~> 1.0", only: :dev},
    {:phoenix_session_process, "~> 0.4.0"}
  ]
end
```

## Next Steps

1. Run benchmarks on your target hardware
2. Establish baseline performance metrics
3. Monitor in production with telemetry
4. Adjust configuration based on results
5. Re-run benchmarks after changes