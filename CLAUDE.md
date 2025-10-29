# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is Phoenix.SessionProcess, an Elixir library that creates a process for each user session in Phoenix applications. All user requests go through their dedicated session process, providing session isolation and state management.

## Key Commands

### Development Commands
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `mix compile --warnings-as-errors` - Compile with strict warnings (CI requirement)
- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run a specific test file
- `mix test test/phoenix/session_process/` - Run all tests in a directory
- `mix format` - Format code
- `mix format --check-formatted` - Check formatting without modifying files (CI requirement)
- `mix credo --strict` - Run static code analysis with strict mode (CI requirement)
- `mix dialyzer` - Run type checking (first run builds PLT cache)
- `mix dialyzer --halt-exit-status` - Run type checking and exit with error code on issues (CI requirement)
- `mix lint` - Run both Credo and Dialyzer (defined in mix.exs aliases)
- `mix docs` - Generate documentation
- `mix hex.publish` - Publish to Hex.pm (requires authentication)

### Code Quality Requirements
Before committing, ensure code passes all CI checks:
1. Compiles without warnings: `mix compile --warnings-as-errors`
2. Properly formatted: `mix format --check-formatted`
3. Passes Credo: `mix credo --strict`
4. Passes Dialyzer: `mix dialyzer --halt-exit-status`

### Testing
The test suite uses ExUnit. Tests are located in the `test/` directory. The test helper (test/test_helper.exs:3) automatically starts the supervisor and configures the default TestProcess module.

### Development Environment
The project uses `devenv` for development environment setup with Nix:
- Elixir 1.18+ with OTP 28+ (minimum: Elixir 1.14, OTP 24)
- Includes git, figlet, and lolcat tools
- Run `devenv shell` to enter the development environment

### Benchmarking
Performance testing available via:
- `mix run bench/simple_bench.exs` - Quick benchmark (5-10 seconds)
- `mix run bench/session_benchmark.exs` - Comprehensive benchmark (30-60 seconds)

Expected performance:
- Session Creation: 10,000+ sessions/sec
- Memory Usage: ~10KB per session
- Registry Lookups: 100,000+ lookups/sec

## Architecture

### Module Organization

The library is organized into several logical groups:

**Core API** (primary interface for users):
- `Phoenix.SessionProcess` - Main public API
- `Phoenix.SessionProcess.SessionId` - Plug for session ID generation

**Internals** (supervision and lifecycle management):
- `Phoenix.SessionProcess.Supervisor` - Top-level supervisor (Note: filename is `superviser.ex`)
- `Phoenix.SessionProcess.ProcessSupervisor` - Dynamic supervisor for sessions (Note: filename is `process_superviser.ex`)
- `Phoenix.SessionProcess.Cleanup` - TTL-based cleanup
- `Phoenix.SessionProcess.DefaultSessionProcess` - Default session implementation

**LiveView Integration**:
- `Phoenix.SessionProcess.LiveView` - PubSub-based LiveView integration helpers (recommended)

**State Management Utilities**:
- `Phoenix.SessionProcess.Redux` - Optional Redux-style state with actions/reducers, subscriptions, and selectors (advanced use cases)
- `Phoenix.SessionProcess.Redux.Selector` - Memoized selectors for efficient derived state
- `Phoenix.SessionProcess.Redux.Subscription` - Subscription management for reactive state changes
- `Phoenix.SessionProcess.Redux.LiveView` - Redux-specific LiveView integration helpers
- `Phoenix.SessionProcess.MigrationExamples` - Migration examples for Redux
- `Phoenix.SessionProcess.ReduxExamples` - Comprehensive Redux usage examples

**Configuration & Error Handling**:
- `Phoenix.SessionProcess.Config` - Configuration management
- `Phoenix.SessionProcess.Error` - Error types and messages

**Observability**:
- `Phoenix.SessionProcess.Telemetry` - Telemetry event emission
- `Phoenix.SessionProcess.TelemetryLogger` - Logging integration
- `Phoenix.SessionProcess.Helpers` - General utilities

### Core Components

1. **Phoenix.SessionProcess** (lib/phoenix/session_process.ex:1)
   - Main module providing the public API
   - Delegates to ProcessSupervisor for actual process management
   - Provides the `:process` macro for basic GenServer functionality
   - The macro injects: `get_session_id/0` helper function
   - **State updates ONLY via Redux.dispatch** - no manual broadcast helpers
   - Note: `:process_link` is deprecated - use `:process` instead
   - Key functions: `start/1-3`, `call/2-3`, `cast/2`, `terminate/1`, `started?/1`, `list_session/0`

2. **Phoenix.SessionProcess.Supervisor** (lib/phoenix/session_process/superviser.ex:1)
   - Top-level supervisor that manages the Registry, ProcessSupervisor, and Cleanup
   - Must be added to the application's supervision tree
   - Supervises: Registry, ProcessSupervisor, and Cleanup GenServer

3. **Phoenix.SessionProcess.ProcessSupervisor** (lib/phoenix/session_process/process_superviser.ex:1)
   - DynamicSupervisor that manages individual session processes
   - Handles starting, terminating, and communicating with session processes
   - Performs session validation and limit checks (max sessions, rate limiting)
   - Emits telemetry events for all operations

4. **Phoenix.SessionProcess.SessionId** (lib/phoenix/session_process/session_id.ex)
   - Plug that generates unique session IDs
   - Must be placed after `:fetch_session` plug in router pipeline
   - Assigns session_id to conn.assigns for use in controllers/LiveViews

5. **Phoenix.SessionProcess.Cleanup** (lib/phoenix/session_process/cleanup.ex:1)
   - GenServer for automatic TTL-based session cleanup
   - Schedules session expiration on creation
   - Runs cleanup tasks periodically

6. **Phoenix.SessionProcess.LiveView** (lib/phoenix/session_process/live_view.ex:1)
   - Redux-based LiveView integration for session processes
   - **Requires Redux** for state management
   - Key functions: `mount_session/3-4` (default state_key: :get_redux_state), `unmount_session/1`, `dispatch/2`, `subscribe/2`
   - Subscribes to Redux PubSub topic: `"session:#{session_id}:redux"`
   - Receives state changes as `{:redux_state_change, %{state: state, action: action, timestamp: timestamp}}`
   - Works across distributed nodes via Phoenix.PubSub

7. **Phoenix.SessionProcess.Redux** (lib/phoenix/session_process/redux.ex:1)
   - Optional Redux-style state management with actions, reducers, subscriptions, and selectors
   - Provides time-travel debugging, middleware support, and action history
   - **Redux.Selector**: Memoized selectors with reselect-style composition for efficient derived state
   - **Redux.Subscription**: Subscribe to state changes with optional selectors (only notifies when selected values change)
   - **Redux.LiveView**: Helper module for Redux-specific LiveView integration
   - **Phoenix.PubSub integration**: Broadcast state changes across nodes for distributed applications
   - **Comprehensive telemetry**: Monitor Redux operations (dispatch, subscribe, selector cache hits/misses, PubSub broadcasts)
   - Best for complex applications requiring reactive UIs, predictable state updates, audit trails, or distributed state
   - Note: Most applications don't need this - standard GenServer state is sufficient

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
- `:process` macro injects GenServer boilerplate
- **Redux-only state management**:
  - All state updates go through `Redux.dispatch(redux, action, reducer)`
  - Redux automatically handles subscriptions and PubSub broadcasts
  - No manual `broadcast_state_change` or `session_topic` helpers
  - Single, predictable way to update state
- **Redux-based LiveView integration** (required for LiveView):
  - Session processes use Redux with PubSub configuration
  - LiveViews subscribe using `Phoenix.SessionProcess.LiveView.mount_session/3-4`
  - Redux PubSub topic: `"session:#{session_id}:redux"`
  - Message format: `{:redux_state_change, %{state: state, action: action, timestamp: timestamp}}`
  - Works across distributed nodes
- Telemetry events for all lifecycle operations (start, stop, call, cast, cleanup, errors)
- Comprehensive error handling with Phoenix.SessionProcess.Error module

## Configuration

The library uses application configuration:
```elixir
config :phoenix_session_process,
  session_process: MySessionProcess,  # Default session module
  max_sessions: 10_000,               # Maximum concurrent sessions
  session_ttl: 3_600_000,            # Session TTL in milliseconds (1 hour)
  rate_limit: 100,                   # Sessions per minute limit
  pubsub: MyApp.PubSub               # Optional: PubSub module for LiveView integration
```

Configuration options:
- `session_process`: Default module for session processes (defaults to `Phoenix.SessionProcess.DefaultSessionProcess`)
- `max_sessions`: Maximum concurrent sessions (defaults to 10,000)
- `session_ttl`: Session TTL in milliseconds (defaults to 1 hour)
- `rate_limit`: Sessions per minute limit (defaults to 100)
- `pubsub`: PubSub module for broadcasting state changes (optional, required for LiveView integration)

## Usage in Phoenix Applications

1. Add supervisor to application supervision tree
2. Add SessionId plug after fetch_session in router
3. Define custom session process modules using the `:process` macro
4. Start processes with session IDs
5. Communicate using call/cast operations
6. For LiveView integration, use `Phoenix.SessionProcess.LiveView` helpers

### LiveView Integration Example (Redux-Only)

**Session Process:**
```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process
  alias Phoenix.SessionProcess.Redux

  @impl true
  def init(_) do
    redux = Redux.init_state(
      %{count: 0, user: nil},
      pubsub: MyApp.PubSub,
      pubsub_topic: "session:#{get_session_id()}:redux"
    )
    {:ok, %{redux: redux}}
  end

  @impl true
  def handle_cast({:increment}, state) do
    # Dispatch action - Redux handles all notifications automatically
    new_redux = Redux.dispatch(state.redux, {:increment}, &reducer/2)
    {:noreply, %{state | redux: new_redux}}
  end

  @impl true
  def handle_call(:get_redux_state, _from, state) do
    {:reply, {:ok, state.redux}, state}
  end

  defp reducer(state, action) do
    case action do
      {:increment} -> %{state | count: state.count + 1}
      _ -> state
    end
  end
end
```

**LiveView:**
```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess.LiveView, as: SessionLV

  def mount(_params, %{"session_id" => session_id}, socket) do
    # Subscribe and get initial Redux state
    case SessionLV.mount_session(socket, session_id, MyApp.PubSub) do
      {:ok, socket, state} ->
        {:ok, assign(socket, state: state)}
      {:error, _} ->
        {:ok, socket}
    end
  end

  # Receive Redux state updates
  def handle_info({:redux_state_change, %{state: new_state}}, socket) do
    {:noreply, assign(socket, state: new_state)}
  end

  def terminate(_reason, socket) do
    SessionLV.unmount_session(socket)
    :ok
  end
end
```

## State Management Architecture

Phoenix.SessionProcess enforces Redux-based state management for LiveView integration.

### Core Principle
All state updates go through Redux dispatch actions.

### State Update Flow
1. Action dispatched: `Redux.dispatch(redux, action, reducer)`
2. Reducer updates state
3. Redux notifies subscriptions (automatic)
4. Redux broadcasts via PubSub (automatic, if configured)
5. LiveViews receive state updates

### No Manual Broadcasting
The library does NOT provide manual broadcast helpers. All notifications
happen automatically through Redux dispatch.

### When to Use Redux
- **Required** if using LiveView integration
- **Optional** for session-only processes without LiveView

### State Management Options

1. **Redux-based State** (Required for LiveView) - Predictable state updates with actions/reducers
   - Use `Redux.dispatch(redux, action, reducer)` to update state
   - Automatic PubSub broadcasting to LiveViews
   - Time-travel debugging, middleware, action history available
   - Use when you need LiveView integration or audit trails

2. **Standard GenServer State** (Session-only) - Full control with standard GenServer callbacks
   - Use `handle_call`, `handle_cast`, and `handle_info` to manage state
   - Simple, idiomatic Elixir
   - Use when no LiveView integration is needed

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
