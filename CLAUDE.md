# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is Phoenix.SessionProcess, an Elixir library that creates a process for each user session in Phoenix applications. All user requests go through their dedicated session process, providing session isolation and state management.

**Current Version**: 1.0.0 (stable release published on hex.pm)
**Repository**: https://github.com/gsmlg-dev/phoenix_session_process
**Hex Package**: https://hex.pm/packages/phoenix_session_process

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

**Behaviours** (define contracts for user modules):
- `Phoenix.SessionProcess.ProcessBehaviour` - Behaviour for session process modules
- `Phoenix.SessionProcess.ReducerBehaviour` - Behaviour for reducer modules

**State Management**:
- `Phoenix.SessionProcess.Action` - Internal action structure for dispatching
- `Phoenix.SessionProcess.ReducerCompiler` - Compile-time reducer validation and code generation

**Configuration & Error Handling**:
- `Phoenix.SessionProcess.Config` - Configuration management
- `Phoenix.SessionProcess.Error` - Error types and messages

**LiveView Integration**:
- `Phoenix.SessionProcess.LiveView` - LiveView integration helpers with Redux Store API

**Observability**:
- `Phoenix.SessionProcess.Telemetry` - Telemetry event emission
- `Phoenix.SessionProcess.TelemetryLogger` - Logging integration
- `Phoenix.SessionProcess.Helpers` - General utilities

### Core Components

1. **Phoenix.SessionProcess** (lib/phoenix/session_process.ex:1)
   - Main module providing the public API
   - Delegates to ProcessSupervisor for actual process management
   - Provides the `:process` and `:reducer` macros with built-in Redux Store infrastructure

   **Basic Functions**:
   - `start_session/1-2` - Start session process (v1.0.0 API)
   - `call/2-3` - Synchronous call to session
   - `cast/2` - Asynchronous cast to session
   - `terminate/1` - Stop session
   - `started?/1` - Check if session exists
   - `list_session/0` - List all sessions

   **Redux Store API (v1.0.0)** - SessionProcess IS the Redux store:
   - `dispatch/4` - Dispatch actions: `dispatch(session_id, type, payload \\ nil, meta \\ [])`
   - `dispatch_async/4` - Convenience alias: `dispatch(id, type, payload, [meta | async: true])`
   - `subscribe/4` - Subscribe with selector
   - `unsubscribe/2` - Remove subscription
   - `get_state/1-2` - Get state (client-side, with optional selector)
   - `select_state/2` - Apply selector on server-side (more efficient for large states)

   **Process Macro Usage**:
   ```elixir
   defmodule MySessionProcess do
     use Phoenix.SessionProcess, :process

     # Define initial state with init_state/1
     @impl true
     def init_state(_args) do
       %{count: 0, user: nil}
     end

     # Optional: Define combined reducers
     @impl true
     def combined_reducers do
       [MyApp.CounterReducer, MyApp.UserReducer]
     end
   end
   ```

   **Note**: The `:process` macro automatically adds `@behaviour Phoenix.SessionProcess.ProcessBehaviour`,
   enabling compile-time warnings when callbacks are missing `@impl` annotations.

   **Reducer Macro Usage** (v1.0.0+):
   ```elixir
   defmodule MyApp.CounterReducer do
     use Phoenix.SessionProcess, :reducer

     # REQUIRED: Name must be an atom
     @name :counter

     # OPTIONAL: Action prefix must be binary or nil
     @action_prefix "counter"

     @impl true
     def init_state do
       %{count: 0}
     end

     # Actions are Action structs with binary types
     @impl true
     def handle_action(action, state) do
       alias Phoenix.SessionProcess.Action

       case action do
         %Action{type: "increment"} ->
           %{state | count: state.count + 1}

         %Action{type: "set", payload: value} ->
           %{state | count: value}

         _ ->
           # Delegate to handle_unmatched_action for logging/debugging
           handle_unmatched_action(action, state)
       end
     end

     # Optional: Handle async actions, must return cancellation callback
     @impl true
     def handle_async(action, dispatch, state) do
       alias Phoenix.SessionProcess.Action

       case action do
         %Action{type: "fetch_data", payload: url} ->
           Task.async(fn ->
             data = HTTPClient.get(url)
             # dispatch has signature: dispatch(type, payload \\ nil, meta \\ [])
             dispatch.("data_received", data)
           end)
           # Return cancellation callback
           fn ->
             # Cancel logic here
             :ok
           end

         _ ->
           handle_unmatched_async(action, dispatch, state)
       end
     end
   end
   ```

   **Note**: The `:reducer` macro automatically adds `@behaviour Phoenix.SessionProcess.ReducerBehaviour`,
   enabling compile-time warnings when callbacks are missing `@impl` annotations.

2. **Phoenix.SessionProcess.Action** (lib/phoenix/session_process/action.ex:1)
   - Internal action structure for fast pattern matching
   - **IMPORTANT**: Action types MUST be binary strings, not atoms
   - Fields:
     - `type` - Action type (binary string, required)
     - `payload` - Action data (any term)
     - `meta` - Action metadata (map internally, keyword list in API)

   **Creating Actions**:
   ```elixir
   # Actions are created internally from dispatch calls
   dispatch(session_id, "increment")  # type: "increment", payload: nil
   dispatch(session_id, "set_user", %{id: 1})  # type: "set_user", payload: %{id: 1}
   dispatch(session_id, "fetch", nil, async: true)  # meta: %{async: true}
   ```

3. **Phoenix.SessionProcess.ProcessBehaviour** (lib/phoenix/session_process/process_behaviour.ex:1)
   - Behaviour defining the contract for session process modules
   - Automatically included when using `use Phoenix.SessionProcess, :process`
   - Defines required callback: `init_state/1`
   - Defines optional callback: `combined_reducers/0`
   - Enables compile-time warnings for missing `@impl` annotations
   - See module documentation for detailed callback specifications

4. **Phoenix.SessionProcess.ReducerBehaviour** (lib/phoenix/session_process/reducer_behaviour.ex:1)
   - Behaviour defining the contract for reducer modules
   - Automatically included when using `use Phoenix.SessionProcess, :reducer`
   - Defines required callbacks: `init_state/0`, `handle_action/2`
   - Defines optional callbacks: `handle_async/3`, `handle_unmatched_action/2`, `handle_unmatched_async/3`
   - Enables compile-time warnings for missing `@impl` annotations
   - See module documentation for detailed callback specifications

5. **Phoenix.SessionProcess.ReducerCompiler** (lib/phoenix/session_process/reducer_compiler.ex:1)
   - Compile-time validation and code generation for reducers
   - Validates `@name` is an atom
   - Validates `@action_prefix` is binary, nil, or ""
   - Generates `get_name/0`, `get_action_prefix/0`, and default callbacks

6. **Phoenix.SessionProcess.Supervisor** (lib/phoenix/session_process/superviser.ex:1)
   - Top-level supervisor that manages the Registry, ProcessSupervisor, and Cleanup
   - Must be added to the application's supervision tree
   - Supervises: Registry, ProcessSupervisor, and Cleanup GenServer

7. **Phoenix.SessionProcess.ProcessSupervisor** (lib/phoenix/session_process/process_superviser.ex:1)
   - DynamicSupervisor that manages individual session processes
   - Handles starting, terminating, and communicating with session processes
   - Performs session validation and limit checks (max sessions, rate limiting)
   - Emits telemetry events for all operations

8. **Phoenix.SessionProcess.SessionId** (lib/phoenix/session_process/session_id.ex)
   - Plug that generates unique session IDs
   - Must be placed after `:fetch_session` plug in router pipeline
   - Assigns session_id to conn.assigns for use in controllers/LiveViews

9. **Phoenix.SessionProcess.Cleanup** (lib/phoenix/session_process/cleanup.ex:1)
   - GenServer for automatic TTL-based session cleanup
   - Schedules session expiration on creation
   - Runs cleanup tasks periodically

10. **Phoenix.SessionProcess.LiveView** (lib/phoenix/session_process/live_view.ex:1)
   - LiveView integration helpers for Redux Store API
   - `mount_store/4` - Mount with direct SessionProcess subscriptions
   - `unmount_store/1` - Unmount (optional, automatic cleanup via monitoring)
   - `dispatch_store/3-4` - Dispatch actions (sync/async)
   - Uses SessionProcess subscriptions (not PubSub)
   - Selector-based updates for efficiency
   - Automatic cleanup via process monitoring

### Process Management Flow

1. Session ID generation via the SessionId plug
2. Process creation through `Phoenix.SessionProcess.start_session/1-2`
3. Validation checks (session ID format, session limits)
4. Processes are registered in `Phoenix.SessionProcess.Registry` with two entries:
   - `{session_id, pid}` for session lookup
   - `{pid, module}` for module tracking
5. Reducers are registered and compiled with validation
6. TTL-based cleanup is scheduled for each session
7. Communication via `call/2-3` and `cast/2`
8. Actions dispatched via `dispatch/4` or `dispatch_async/4`
9. Automatic cleanup when processes terminate or TTL expires

### Key Design Patterns

- Uses Registry for bidirectional lookups (session_id ↔ pid, pid ↔ module)
- DynamicSupervisor for on-demand process creation
- `:process` macro injects GenServer boilerplate + Redux Store infrastructure
- `:reducer` macro provides compile-time validation and code generation

- **Redux Store API** - SessionProcess IS the Redux store:
  - All state updates go through `dispatch(session_id, type, payload, meta)`
  - **CRITICAL**: Action types MUST be binary strings (e.g., "increment", "user.set")
  - Subscriptions use selectors for efficiency
  - Automatic subscription cleanup via process monitoring
  - No separate Redux struct needed
  - Async actions return cancellation callbacks

- **Type Constraints (v1.0.0+)**:
  - Reducer `@name` MUST be an atom (compile-time enforced)
  - Action types MUST be binary strings (runtime enforced)
  - Reducer `@action_prefix` MUST be binary, nil, or "" (compile-time enforced)
  - `dispatch/4` signature: `dispatch(session_id, type, payload \\ nil, meta \\ [])`
    - `type`: binary string (required)
    - `payload`: any term (defaults to nil)
    - `meta`: keyword list (defaults to [])
  - `dispatch_async/4` is an alias for `dispatch(id, type, payload, [meta | async: true])`
  - `handle_async/3` MUST return cancellation callback `(() -> any())` for internal use

- **Unmatched Action Handling**:
  - Reducers can override `handle_unmatched_action/2` to customize behavior for unmatched actions
  - Reducers can override `handle_unmatched_async/3` to customize behavior for unmatched async actions
  - Global handler configured via `unmatched_action_handler` config option (:log, :warn, :silent, or custom function)
  - Default behavior logs debug message suggesting use of `@action_prefix` to limit action routing
  - Useful for debugging action routing issues in complex applications

- **LiveView Integration**:
  - Use `Phoenix.SessionProcess.LiveView.mount_store/4` for direct subscriptions
  - Selector-based updates for efficiency
  - Message format: `{event_name, selected_value}`
  - Automatic cleanup when LiveView terminates

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
  unmatched_action_handler: :log     # How to handle unmatched actions (:log, :warn, :silent, or function)
```

Configuration options:
- `session_process`: Default module for session processes (defaults to `Phoenix.SessionProcess.DefaultSessionProcess`)
- `max_sessions`: Maximum concurrent sessions (defaults to 10,000)
- `session_ttl`: Session TTL in milliseconds (defaults to 1 hour)
- `rate_limit`: Sessions per minute limit (defaults to 100)
- `unmatched_action_handler`: How to handle actions that don't match any pattern in reducers (defaults to `:log`)
  - `:log` - Log debug messages for unmatched actions
  - `:warn` - Log warning messages for unmatched actions
  - `:silent` - No logging
  - Custom function with arity 3: `fn action, reducer_module, reducer_name -> ... end`

## Usage in Phoenix Applications

1. Add supervisor to application supervision tree
2. Add SessionId plug after fetch_session in router
3. Define custom session process modules using the `:process` macro
4. Define reducers using the `:reducer` macro (v1.0.0+)
5. Start processes with session IDs
6. Dispatch actions using `dispatch/4` with binary action types
7. For LiveView integration, use `Phoenix.SessionProcess.LiveView` helpers

### Complete Example (v1.0.0)

**1. Define Reducers:**
```elixir
defmodule MyApp.CounterReducer do
  use Phoenix.SessionProcess, :reducer

  @name :counter  # MUST be atom
  @action_prefix "counter"  # MUST be binary or nil

  def init_state do
    %{count: 0}
  end

  def handle_action(action, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "increment"} ->
        %{state | count: state.count + 1}

      %Action{type: "set", payload: value} ->
        %{state | count: value}

      _ ->
        state
    end
  end
end

defmodule MyApp.UserReducer do
  use Phoenix.SessionProcess, :reducer

  @name :user
  @action_prefix "user"

  def init_state do
    %{current_user: nil, preferences: %{}}
  end

  def handle_action(action, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "set", payload: user} ->
        %{state | current_user: user}

      %Action{type: "update_preferences", payload: prefs} ->
        %{state | preferences: Map.merge(state.preferences, prefs)}

      _ ->
        state
    end
  end

  # Async action example - MUST return cancellation callback
  def handle_async(action, dispatch, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "fetch", payload: user_id} ->
        task = Task.async(fn ->
          user = MyApp.Users.get(user_id)
          # dispatch signature: dispatch(type, payload \\ nil, meta \\ [])
          dispatch.("user.set", user)
        end)

        # Return cancellation callback
        fn ->
          Task.shutdown(task, :brutal_kill)
          :ok
        end

      _ ->
        fn -> nil end
    end
  end
end
```

**2. Define Session Process:**
```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  def init_state(_args) do
    %{}
  end

  def combined_reducers do
    [MyApp.CounterReducer, MyApp.UserReducer]
  end
end
```

**3. Configure Application:**
```elixir
# config/config.exs
config :phoenix_session_process,
  session_process: MyApp.SessionProcess,
  max_sessions: 10_000,
  session_ttl: 3_600_000,
  unmatched_action_handler: :log  # Optional: :log | :warn | :silent | custom function

# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    {Phoenix.SessionProcess, []},
    # Or: Phoenix.SessionProcess.Supervisor,
    # ... other children
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**4. Add Plug to Router:**
```elixir
# lib/my_app_web/router.ex
pipeline :browser do
  plug :fetch_session
  plug Phoenix.SessionProcess.SessionId  # After :fetch_session
  # ... other plugs
end
```

**5. Use in Controller:**
```elixir
defmodule MyAppWeb.PageController do
  use MyAppWeb, :controller
  alias Phoenix.SessionProcess

  def index(conn, _params) do
    session_id = conn.assigns.session_id

    # Start session
    {:ok, _pid} = SessionProcess.start_session(session_id)

    # Dispatch actions (MUST use binary types)
    :ok = SessionProcess.dispatch(session_id, "counter.increment")
    :ok = SessionProcess.dispatch(session_id, "user.set", %{id: 1, name: "Alice"})

    # Async dispatch (convenience - automatically adds async: true)
    :ok = SessionProcess.dispatch_async(session_id, "user.fetch", 123)

    # Equivalent to:
    # :ok = SessionProcess.dispatch(session_id, "user.fetch", 123, async: true)

    # Get state
    state = SessionProcess.get_state(session_id)
    # => %{counter: %{count: 1}, user: %{current_user: %{id: 1, name: "Alice"}}}

    render(conn, "index.html", state: state)
  end
end
```

**6. LiveView Integration:**
```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.LiveView, as: SessionLV

  def mount(_params, %{"session_id" => session_id}, socket) do
    # Mount with store subscription
    case SessionLV.mount_store(
      socket,
      session_id,
      fn state -> state.counter.count end,
      :count_changed
    ) do
      {:ok, socket, initial_count} ->
        {:ok, assign(socket, count: initial_count, session_id: session_id)}
      {:error, _} ->
        {:ok, socket}
    end
  end

  # Receive state updates
  def handle_info({:count_changed, new_count}, socket) do
    {:noreply, assign(socket, count: new_count)}
  end

  # Dispatch actions (MUST use binary types)
  def handle_event("increment", _params, socket) do
    # Async dispatch returns cancellation
    {:ok, _cancel_fn} = SessionLV.dispatch_store(
      socket.assigns.session_id,
      "counter.increment",
      async: true
    )
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    # Cleanup is automatic via process monitoring
    SessionLV.unmount_store(socket)
    :ok
  end
end
```

## State Management

Phoenix.SessionProcess uses a Redux-like architecture where SessionProcess itself is the Redux store:

**Core Principles**:
1. **SessionProcess IS the Redux store** - no separate struct needed
2. **Actions MUST have binary types** - not atoms (e.g., "increment", not :increment)
3. **Reducers are namespaced** - state is organized by reducer name (atom)
4. **Async actions return cancellation** - `{:ok, cancel_fn}`

**State Update Flow**:
1. Action dispatched: `dispatch(session_id, "action_type", payload, meta)`
2. Action normalized to `%Action{type: "action_type", payload: payload, meta: %{}}`
3. Registered reducers transform their slice of state
4. SessionProcess notifies subscriptions automatically
5. Subscribers with matching selectors receive updates
6. Dead subscriptions cleaned up automatically via process monitoring

**State Structure**:
```elixir
%{
  counter: %{count: 0},          # From CounterReducer
  user: %{current_user: nil},    # From UserReducer
  # ... other reducer states
}
```

**Selector Functions**:
```elixir
# Client-side selection (get_state/2)
count = SessionProcess.get_state(session_id, fn s -> s.counter.count end)

# Server-side selection (select_state/2) - more efficient for large states
count = SessionProcess.select_state(session_id, fn s -> s.counter.count end)
```

**Subscriptions**:
```elixir
# Subscribe to state changes with selector
{:ok, sub_id} = SessionProcess.subscribe(
  session_id,
  fn state -> state.counter.count end,
  :count_changed,
  self()
)

# Receive updates when selected value changes
receive do
  {:count_changed, new_count} -> IO.puts("Count is now: #{new_count}")
end

# Unsubscribe (optional, automatic cleanup via monitoring)
:ok = SessionProcess.unsubscribe(session_id, sub_id)
```

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

## Important Notes for Code Changes

1. **Action Types MUST Be Binary**: Never use atoms for action types. Always use strings.
   ```elixir
   # CORRECT
   dispatch(session_id, "increment")
   dispatch(session_id, "user.set", user)

   # WRONG
   dispatch(session_id, :increment)  # Will raise ArgumentError
   ```

2. **Reducer Names MUST Be Atoms**: The `@name` attribute must be an atom.
   ```elixir
   # CORRECT
   @name :counter

   # WRONG
   @name "counter"  # Compile error
   ```

3. **Meta is Keyword List in API, Map Internally**:
   ```elixir
   # API uses keyword list
   dispatch(session_id, "action", nil, async: true, foo: :bar)

   # Internally converted to map
   %Action{meta: %{async: true, foo: :bar}}
   ```

4. **handle_async MUST Return Cancellation Callback**:
   ```elixir
   # CORRECT
   def handle_async(action, dispatch, state) do
     fn -> :ok end  # Return cancel function
   end

   # WRONG
   def handle_async(action, dispatch, state) do
     state  # Don't return state!
   end
   ```

5. **dispatch_async is Convenience Alias**:
   ```elixir
   # These are equivalent:
   :ok = dispatch_async(session_id, "fetch", data)
   :ok = dispatch(session_id, "fetch", data, async: true)

   # Cancellation is handled internally via handle_async/3 callback in reducer
   ```

6. **Prefer select_state/2 for Large States**:
   ```elixir
   # Server-side selection - more efficient
   count = SessionProcess.select_state(session_id, fn s -> s.counter.count end)

   # Client-side selection - transfers full state
   count = SessionProcess.get_state(session_id, fn s -> s.counter.count end)
   ```

7. **Unmatched Action Handling**:
   ```elixir
   # Default behavior: logs debug message for unmatched actions
   def handle_action(action, state) do
     case action do
       %Action{type: "known"} -> # handle action
       _ -> handle_unmatched_action(action, state)  # Logs debug message
     end
   end

   # Override to customize behavior
   def handle_unmatched_action(action, state) do
     # Custom logic, e.g., track unmatched actions
     MyApp.Metrics.track_unmatched(action)
     state
   end

   # Or configure globally
   config :phoenix_session_process,
     unmatched_action_handler: :warn  # :log | :warn | :silent | custom function
   ```
