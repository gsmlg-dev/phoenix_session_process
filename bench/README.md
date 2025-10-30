# Phoenix Session Process Benchmarking Guide

This directory contains comprehensive benchmarking tools to measure the performance of the Phoenix Session Process library.

## Overview

The benchmarking suite provides tools to measure:
- Session creation and termination performance
- Memory usage and efficiency
- Concurrent operation throughput
- Registry lookup performance
- Redux Store dispatch performance (sync/async/concurrent)
- State selector performance (client vs server-side)
- Subscription notification performance
- Error handling performance

## Files

- **`simple_bench.exs`** - Quick performance test (5-10 seconds)
- **`session_benchmark.exs`** - Comprehensive benchmark (30-60 seconds)
- **`dispatch_benchmark.exs`** - Dispatch performance benchmark (30-45 seconds)
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

### Dispatch Performance Benchmark
Run dispatch-specific performance tests:

```bash
mix run bench/dispatch_benchmark.exs
```

**Sample Output:**
```
🚀 Phoenix Session Process - Dispatch Performance Benchmark
============================================================

📊 1. Synchronous Dispatch Throughput
----------------------------------------
    100 dispatches:    8788.89 ops/sec  (avg: 0.114ms/op)
    500 dispatches:   40936.63 ops/sec  (avg: 0.024ms/op)
   5000 dispatches:  185185.19 ops/sec  (avg: 0.005ms/op)

📊 2. Async Dispatch with Cancellation
----------------------------------------
    100 async dispatches:  211416.49 ops/sec  (avg: 0.005ms/op)
   1000 async dispatches:  310848.62 ops/sec  (avg: 0.003ms/op)

📊 3. Concurrent Dispatch Operations
----------------------------------------
   10 tasks × 100 dispatches:   18886.45 ops/sec
  100 tasks × 100 dispatches:  141191.09 ops/sec

📊 4. Dispatch with Active Subscriptions
----------------------------------------
   1 subscriptions:    1962.67 ops/sec
  10 subscriptions:    1928.42 ops/sec

📊 5. Action Type Performance Comparison
----------------------------------------
  No-op (no state change)       :    77627.7 ops/sec
  Increment (state change)      :   66965.78 ops/sec

📊 6. State Selector Performance
----------------------------------------
  Simple field access (client)       :  316866.82 ops/sec
  Simple field access (server)       :  330076.58 ops/sec
```

### Comprehensive Session Benchmark Output
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

## GitHub Actions Integration

### Automated Benchmark Runs

Benchmarks are automatically run on pull requests to ensure performance regressions are caught early.

#### On Pull Requests
All benchmarks run automatically when you create a pull request to `main` or `develop` branches:

```yaml
# Triggered automatically on PR
- Simple Benchmark
- Session Benchmark
- Dispatch Benchmark
```

Results appear in the GitHub Actions workflow logs under the "Benchmark" workflow.

#### Manual Trigger
You can also manually trigger benchmarks from the GitHub Actions tab:

1. Go to **Actions** tab in the repository
2. Select **Benchmark** workflow from the left sidebar
3. Click **Run workflow** button
4. Choose which benchmark to run:
   - **all** - Run all benchmarks (default)
   - **simple** - Quick performance check only
   - **session** - Comprehensive session lifecycle only
   - **dispatch** - Dispatch performance only
5. Click **Run workflow** to start

#### Workflow Configuration
The benchmark workflow is defined in `.github/workflows/benchmark.yml`:

```yaml
name: Benchmark

on:
  pull_request:
    branches: [ main, develop ]
  workflow_dispatch:
    inputs:
      benchmark:
        type: choice
        options:
          - all
          - simple
          - session
          - dispatch
```

#### Viewing Results
Benchmark results are displayed in:
1. **Workflow logs**: Detailed output with all metrics
2. **Step summary**: Quick overview of benchmarks run
3. **PR comments**: (Optional) Can be configured to post results as PR comments

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