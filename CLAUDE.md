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
- `Phoenix.SessionProcess.LiveView` - LiveView integration helpers with Redux Store API (v0.6.0+)
  - **New API**: `mount_store/4`, `unmount_store/1`, `dispatch_store/3` (recommended)
  - **Legacy API**: `mount_session/4`, `unmount_session/1` (deprecated, still works)

**State Management Utilities**:
- **Redux Store API (v0.6.0+)**: Built directly into `Phoenix.SessionProcess` (recommended)
  - SessionProcess IS the Redux store - no separate struct needed
  - Functions: `dispatch/3`, `subscribe/4`, `register_reducer/3`, `register_selector/3`, `get_state/2`
  - 70% less boilerplate than old Redux API

- **Legacy Redux Module** (deprecated as of v0.6.0):
  - `Phoenix.SessionProcess.Redux` - Separate Redux struct (deprecated, still works)
  - `Phoenix.SessionProcess.Redux.Selector` - Memoized selectors
  - `Phoenix.SessionProcess.Redux.Subscription` - Subscription management
  - Migration guide: `REDUX_TO_SESSIONPROCESS_MIGRATION.md`

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
   - Provides the `:process` macro with built-in Redux Store infrastructure (v0.6.0+)
   - The macro injects: `get_session_id/0` helper and Redux infrastructure
   - Note: `:process_link` is deprecated - use `:process` instead

   **Basic Functions**:
   - `start/1-3` - Start session process
   - `call/2-3` - Synchronous call to session
   - `cast/2` - Asynchronous cast to session
   - `terminate/1` - Stop session
   - `started?/1` - Check if session exists
   - `list_session/0` - List all sessions

   **Redux Store API (v0.6.0+)** - SessionProcess IS the Redux store:
   - `dispatch/3` - Dispatch actions (sync or async)
   - `subscribe/4` - Subscribe with selector
   - `unsubscribe/2` - Remove subscription
   - `register_reducer/3` - Register named reducer
   - `register_selector/3` - Register named selector
   - `get_state/2` - Get state (with optional selector)
   - `select/2` - Apply registered selector

   **Process Macro Usage**:
   ```elixir
   defmodule MySessionProcess do
     use Phoenix.SessionProcess, :process

     # NEW: Define initial state with user_init/1
     def user_init(_args) do
       %{count: 0, user: nil}
     end
   end
   ```

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
   - LiveView integration helpers for Redux Store API

   **New Redux Store API (v0.6.0+)** - Recommended:
   - `mount_store/4` - Mount with direct SessionProcess subscriptions
   - `unmount_store/1` - Unmount (optional, automatic cleanup via monitoring)
   - `dispatch_store/3` - Dispatch actions (sync/async)
   - Uses SessionProcess subscriptions (not PubSub)
   - Selector-based updates for efficiency
   - Automatic cleanup via process monitoring

   **Legacy Redux API** (deprecated, still works):
   - `mount_session/3-4` - Mount with PubSub (default state_key: :get_redux_state)
   - `unmount_session/1` - Unmount from PubSub
   - `dispatch/2`, `dispatch_async/2` - Generic dispatch helpers
   - Uses PubSub topic: `"session:#{session_id}:redux"`
   - Message format: `{:redux_state_change, %{state: state, action: action, timestamp: timestamp}}`

7. **Phoenix.SessionProcess.Redux** (lib/phoenix/session_process/redux.ex:1) - **DEPRECATED as of v0.6.0**
   - **Use the new Redux Store API instead** (built into SessionProcess)
   - Old Redux struct-based state management (deprecated, still works)
   - Requires managing separate Redux struct: `%Redux{current_state: ...}`
   - Functions marked with `@deprecated` annotations
   - Runtime deprecation warnings guide migration
   - Migration guide: `REDUX_TO_SESSIONPROCESS_MIGRATION.md`

   **Legacy features** (all moved to SessionProcess in v0.6.0):
   - Actions, reducers, subscriptions, selectors
   - Time-travel debugging, middleware, action history
   - PubSub integration for distributed state

   **Migration path**:
   - Old: `Redux.init_state(...)` → New: `def user_init(_), do: %{...}`
   - Old: `Redux.dispatch(redux, action, reducer)` → New: `SessionProcess.dispatch(session_id, action)`
   - Old: `Redux.subscribe(redux, selector, callback)` → New: `SessionProcess.subscribe(session_id, selector, event, pid)`

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
- `:process` macro injects GenServer boilerplate + Redux Store infrastructure (v0.6.0+)

- **Redux Store API (v0.6.0+)** - SessionProcess IS the Redux store:
  - All state updates go through `SessionProcess.dispatch(session_id, action)`
  - Subscriptions use selectors: `SessionProcess.subscribe(session_id, selector, event, pid)`
  - Automatic subscription cleanup via process monitoring
  - No separate Redux struct needed - just return state from `user_init/1`
  - 70% less boilerplate than old Redux API

- **LiveView Integration (v0.6.0+)**:
  - Use `Phoenix.SessionProcess.LiveView.mount_store/4` for direct subscriptions
  - No PubSub configuration needed
  - Selector-based updates for efficiency
  - Message format: `{event_name, selected_value}`
  - Automatic cleanup when LiveView terminates

- **Legacy Redux API** (deprecated):
  - Old struct-based Redux (still works but deprecated)
  - PubSub-based LiveView integration (still works but deprecated)
  - Migration guide available

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

### LiveView Integration Example (New Redux Store API - v0.6.0+)

**Session Process:**
```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  # NEW: Just define initial state with user_init/1
  def user_init(_args) do
    %{count: 0, user: nil}
  end
end
```

**Register Reducer and Use:**
```elixir
# In your controller or LiveView mount:
session_id = conn.assigns.session_id

# Start session
Phoenix.SessionProcess.start(session_id, MyApp.SessionProcess)

# Register reducer
reducer = fn state, action ->
  case action do
    :increment -> %{state | count: state.count + 1}
    {:set_user, user} -> %{state | user: user}
    _ -> state
  end
end

Phoenix.SessionProcess.register_reducer(session_id, :main, reducer)

# Dispatch actions
{:ok, new_state} = Phoenix.SessionProcess.dispatch(session_id, :increment)
```

**LiveView (NEW API):**
```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.LiveView, as: SessionLV

  def mount(_params, %{"session_id" => session_id}, socket) do
    # NEW: mount_store with direct subscription
    case SessionLV.mount_store(socket, session_id) do
      {:ok, socket, state} ->
        {:ok, assign(socket, state: state, session_id: session_id)}
      {:error, _} ->
        {:ok, socket}
    end
  end

  # NEW: Receive state updates (simpler message format!)
  def handle_info({:state_changed, new_state}, socket) do
    {:noreply, assign(socket, state: new_state)}
  end

  # NEW: Dispatch actions directly
  def handle_event("increment", _params, socket) do
    :ok = SessionLV.dispatch_store(socket.assigns.session_id, :increment, async: true)
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    # NEW: Cleanup is automatic via process monitoring!
    # But you can explicitly unmount if desired:
    SessionLV.unmount_store(socket)
    :ok
  end
end
```

**Benefits of New API:**
- 70% less boilerplate
- No Redux struct management
- No PubSub configuration
- Automatic cleanup
- Simpler message format
```

## State Management Options

Phoenix.SessionProcess provides two approaches to state management:

### 1. Redux Store API (v0.6.0+) - Recommended

SessionProcess itself is a Redux store with built-in infrastructure:

**Core Principle**: SessionProcess IS the Redux store - no separate struct needed.

**State Update Flow**:
1. Action dispatched: `SessionProcess.dispatch(session_id, action)`
2. Registered reducers transform state
3. SessionProcess notifies subscriptions (automatic)
4. Subscribers with matching selectors receive updates
5. Dead subscriptions cleaned up automatically via process monitoring

**Benefits**:
- 70% less boilerplate
- No Redux struct management
- Direct SessionProcess integration
- Automatic subscription cleanup
- Selector-based updates for efficiency

**Usage**:
```elixir
# Define initial state
def user_init(_), do: %{count: 0}

# Register reducer
SessionProcess.register_reducer(session_id, :counter, fn state, action ->
  case action do
    :increment -> %{state | count: state.count + 1}
    _ -> state
  end
end)

# Dispatch actions
{:ok, new_state} = SessionProcess.dispatch(session_id, :increment)

# Subscribe with selector
{:ok, sub_id} = SessionProcess.subscribe(
  session_id,
  fn state -> state.count end,
  :count_changed,
  self()
)
```

### 2. Legacy Redux Module (Deprecated)

Old struct-based Redux (still works but deprecated):

**Core Principle**: Manage separate `%Redux{}` struct in process state.

**Deprecated as of v0.6.0** - use Redux Store API instead.

**Migration Guide**: See `REDUX_TO_SESSIONPROCESS_MIGRATION.md`

### 3. Standard GenServer State (Basic)

For simple session-only processes without LiveView:

**Usage**: Standard `handle_call`, `handle_cast`, and `handle_info` callbacks

**When to use**: Simple state management without LiveView integration

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
