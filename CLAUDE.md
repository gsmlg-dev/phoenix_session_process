# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is Phoenix.SessionProcess, an Elixir library that creates a process for each user session in Phoenix applications. All user requests go through their dedicated session process, providing session isolation and state management.

## Key Commands

### Development Commands
- `mix deps.get` - Install dependencies
- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run a specific test file
- `mix compile` - Compile the project
- `mix docs` - Generate documentation
- `mix format` - Format code
- `mix hex.publish` - Publish to Hex.pm (requires authentication)

### Testing
The test suite uses ExUnit. Tests are located in the `test/` directory. The test helper (test/test_helper.exs:3) automatically starts the supervisor.

### Development Environment
The project uses `devenv` for development environment setup with Nix. Key configuration:
- Uses Elixir/BEAM 27
- Runs `hello` script on shell entry for greeting
- Includes git, figlet, and lolcat tools

### Benchmarking
Performance testing available via:
- `mix run bench/simple_bench.exs` - Quick benchmark (5-10 seconds)
- `mix run bench/session_benchmark.exs` - Comprehensive benchmark (30-60 seconds)

Expected performance:
- Session Creation: 10,000+ sessions/sec
- Memory Usage: ~10KB per session
- Registry Lookups: 100,000+ lookups/sec

## Architecture

### Core Components

1. **Phoenix.SessionProcess** (lib/phoenix/session_process.ex:1)
   - Main module providing the public API
   - Delegates to ProcessSupervisor for actual process management
   - Provides two macros: `:process` (basic) and `:process_link` (with LiveView monitoring)

2. **Phoenix.SessionProcess.Supervisor** (lib/phoenix/session_process/superviser.ex:1)
   - Top-level supervisor that manages the Registry, ProcessSupervisor, and Cleanup
   - Must be added to the application's supervision tree

3. **Phoenix.SessionProcess.ProcessSupervisor** (lib/phoenix/session_process/process_superviser.ex:1)
   - DynamicSupervisor that manages individual session processes
   - Handles starting, terminating, and communicating with session processes
   - Performs session validation and limit checks

4. **Phoenix.SessionProcess.SessionId** (lib/phoenix/session_process/session_id.ex)
   - Plug that generates unique session IDs
   - Must be placed after `:fetch_session` plug

5. **Phoenix.SessionProcess.Cleanup** (lib/phoenix/session_process/cleanup.ex:1)
   - Automatic TTL-based session cleanup
   - Schedules session expiration on creation

6. **Phoenix.SessionProcess.Redux** (lib/phoenix/session_process/redux.ex:1)
   - Redux-style state management with actions and reducers
   - Provides time-travel debugging, middleware support, and action history

7. **Phoenix.SessionProcess.State** (lib/phoenix/session_process/state.ex:1)
   - Agent-based state storage with Redux-style dispatch support
   - Used for simpler state management scenarios

### Process Management Flow

1. Session ID generation via the SessionId plug
2. Process creation through `Phoenix.SessionProcess.start/1-3`
3. Validation checks (session ID format, session limits)
4. Processes are registered in `Phoenix.SessionProcess.Registry` with two entries:
   - `{session_id, pid}` for session lookup
   - `{pid, module}` for module tracking
5. TTL-based cleanup is scheduled for each session
6. Communication via `call/2-3` and `cast/2`
7. Automatic cleanup when processes terminate or TTL expires

### Key Design Patterns

- Uses Registry for bidirectional lookups (session_id ↔ pid, pid ↔ module)
- DynamicSupervisor for on-demand process creation
- Macros inject GenServer boilerplate and provide `get_session_id/0` helper
- `:process_link` macro adds LiveView monitoring: sessions monitor LiveView processes and send `:session_expired` message on termination
- Telemetry events for all lifecycle operations (start, stop, call, cast, cleanup, errors)
- Comprehensive error handling with Phoenix.SessionProcess.Error module

## Configuration

The library uses application configuration:
```elixir
config :phoenix_session_process,
  session_process: MySessionProcess,  # Default session module
  max_sessions: 10_000,               # Maximum concurrent sessions
  session_ttl: 3_600_000,            # Session TTL in milliseconds (1 hour)
  rate_limit: 100                    # Sessions per minute limit
```

Configuration options:
- `session_process`: Default module for session processes (defaults to `Phoenix.SessionProcess.DefaultSessionProcess`)
- `max_sessions`: Maximum concurrent sessions (defaults to 10,000)
- `session_ttl`: Session TTL in milliseconds (defaults to 1 hour)
- `rate_limit`: Sessions per minute limit (defaults to 100)

## Usage in Phoenix Applications

1. Add supervisor to application supervision tree
2. Add SessionId plug after fetch_session in router
3. Define custom session process modules using `:process` or `:process_link` macros
4. Start processes with session IDs
5. Communicate using call/cast operations

## State Management Options

The library provides three state management approaches:

1. **Basic GenServer** - Full control with standard GenServer callbacks
2. **Phoenix.SessionProcess.State** - Agent-based with simple get/put and Redux dispatch
3. **Phoenix.SessionProcess.Redux** - Full Redux pattern with actions, reducers, middleware, time-travel debugging

## Telemetry and Error Handling

### Telemetry Events
The library emits comprehensive telemetry events for monitoring:
- `[:phoenix, :session_process, :start]` - Session starts
- `[:phoenix, :session_process, :stop]` - Session stops
- `[:phoenix, :session_process, :start_error]` - Session start errors
- `[:phoenix, :session_process, :call]` - Call operations
- `[:phoenix, :session_process, :cast]` - Cast operations
- `[:phoenix, :session_process, :communication_error]` - Communication errors
- `[:phoenix, :session_process, :cleanup]` - Session cleanup
- `[:phoenix, :session_process, :cleanup_error]` - Cleanup errors

Events include metadata (session_id, module, pid) and measurements (duration in native time units).

### Error Types
Common error responses:
- `{:error, {:invalid_session_id, session_id}}` - Invalid session ID format
- `{:error, {:session_limit_reached, max_sessions}}` - Maximum sessions exceeded
- `{:error, {:session_not_found, session_id}}` - Session doesn't exist
- `{:error, {:timeout, timeout}}` - Operation timed out

Use `Phoenix.SessionProcess.Error.message/1` for human-readable error messages.
