# Phoenix.SessionProcess

[![Hex Version](https://img.shields.io/hexpm/v/phoenix_session_process.svg)](https://hex.pm/packages/phoenix_session_process)
[![Hex Docs](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/phoenix_session_process/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A powerful Phoenix library that enables **reusable, composable reducers** for managing user session state. Build modular state management logic once, and reuse it across your entire application with Redux-style patterns in isolated per-session processes.

## Why Phoenix.SessionProcess?

Traditional session management stores session data in external stores (Redis, database) or relies on plug-based state, making it difficult to create reusable state management patterns. **Phoenix.SessionProcess** solves this by combining:

1. **Reusable Reducers** - Write state management logic once, reuse everywhere
2. **Redux-Style Architecture** - Familiar patterns: actions, reducers, selectors, and subscriptions
3. **Session Isolation** - Each user gets their own GenServer process with isolated state
4. **Zero Dependencies** - No Redis, no database, pure OTP/Elixir solution
5. **LiveView Ready** - Built-in reactive subscriptions for real-time UIs

### The Reducer Advantage

Define your state management logic once as reusable reducers:

```elixir
# Define once - use everywhere
defmodule MyApp.CartReducer do
  use Phoenix.SessionProcess, :reducer

  @name :cart
  @action_prefix "cart"

  def init_state, do: %{items: [], total: 0}

  def handle_action(%Action{type: "add_item", payload: item}, state) do
    %{state |
      items: [item | state.items],
      total: state.total + item.price
    }
  end
end
```

Then compose multiple reducers in any session:
```elixir
def combined_reducers do
  [MyApp.CartReducer, MyApp.UserReducer, MyApp.PreferencesReducer]
end
```

**Benefits:**
- **Modularity** - Each reducer manages one slice of state
- **Reusability** - Share reducers across different session types
- **Testability** - Test reducers in isolation
- **Composability** - Combine reducers to build complex state
- **Type Safety** - Compile-time validation of reducer structure

## Features

### Core Features
- **Reusable Reducers** (v1.0.0): Define state management logic once, use across multiple session types
- **Redux Store Architecture**: Built-in Redux with actions, reducers, selectors, and subscriptions
- **Session Isolation**: Each user runs in their own GenServer process with isolated state
- **Composable State**: Combine multiple reducers to build complex session state
- **Compile-Time Validation**: Type checking for reducer names, action types, and structure

### Developer Experience
- **Familiar Patterns**: Redux-style state management developers already know
- **Zero Dependencies**: Pure OTP/Elixir solution - no Redis, no database
- **LiveView Integration**: Reactive subscriptions for real-time UI updates
- **Easy Testing**: Test reducers in isolation without spinning up sessions
- **Extensible**: Custom session process modules with full GenServer support

### Production Ready
- **High Performance**: 10,000+ sessions/second creation rate
- **Automatic Cleanup**: TTL-based session expiration and memory management
- **Comprehensive Monitoring**: Built-in telemetry events for observability
- **Rate Limiting**: Built-in protection against session abuse
- **Error Handling**: Detailed error reporting and human-readable messages

## Installation

Add `phoenix_session_process` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_session_process, "~> 1.0"}
  ]
end
```

### Requirements

- Elixir 1.14+
- Erlang/OTP 24+
- Phoenix 1.6+ (recommended)

## Quick Start

### 1. Add to Supervision Tree

Add the supervisor to your application's supervision tree:

```elixir
# in lib/my_app/application.ex
def start(_type, _args) do
  children = [
    # ... other children ...
    {Phoenix.SessionProcess, []}
    # Or use: {Phoenix.SessionProcess.Supervisor, []}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### 2. Configure Session ID Generation

Add the session ID plug after `:fetch_session` in your router:

```elixir
# in lib/my_app_web/router.ex
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug Phoenix.SessionProcess.SessionId  # Add this line
  # ... other plugs ...
end
```

### 3. Basic Usage

In your controllers, start and use session processes:

```elixir
defmodule MyAppWeb.PageController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    session_id = get_session(conn, :session_id)

    # Start session process
    {:ok, _pid} = Phoenix.SessionProcess.start_session(session_id)
    
    # Store user data
    Phoenix.SessionProcess.cast(session_id, {:put, :user_id, conn.assigns.current_user.id})
    Phoenix.SessionProcess.cast(session_id, {:put, :last_seen, DateTime.utc_now()})
    
    render(conn, "index.html")
  end
end
```

## Configuration

Configure the library in your `config/config.exs`:

```elixir
config :phoenix_session_process,
  session_process: MyApp.SessionProcess,  # Default session module
  max_sessions: 10_000,                   # Maximum concurrent sessions
  session_ttl: 3_600_000,                # Session TTL in milliseconds (1 hour)
  rate_limit: 100,                       # Sessions per minute limit
  unmatched_action_handler: :log         # How to handle unmatched actions (:log, :warn, :silent, or function)
```

## Usage Examples

### Basic Session Process

Create a simple session process to store user state:

```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init(_init_arg) do
    {:ok, %{user_id: nil, preferences: %{}}}
  end

  @impl true
  def handle_call(:get_user, _from, state) do
    {:reply, state.user_id, state}
  end

  @impl true
  def handle_cast({:set_user, user_id}, state) do
    {:noreply, %{state | user_id: user_id}}
  end
end
```

### Redux Store API (v1.0.0) - Reusable Reducers

Phoenix.SessionProcess enables **reusable reducer patterns** - define your state management logic once, and compose it across different session types. **SessionProcess IS the Redux store**, providing familiar Redux patterns with true modularity.

#### Defining Reusable Reducers

Create self-contained reducers that can be shared across your application:

```elixir
defmodule MyApp.CounterReducer do
  use Phoenix.SessionProcess, :reducer

  @name :counter  # MUST be atom
  @action_prefix "counter"  # MUST be binary

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

defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init_state(_args) do
    %{}
  end

  # Compose reducers - mix and match for different session types
  @impl true
  def combined_reducers do
    [MyApp.CounterReducer]
  end
end

# Reuse the same reducers in different session types
defmodule MyApp.AdminSessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init_state(_args), do: %{}

  @impl true
  def combined_reducers do
    # Admin sessions get counter + additional audit logging
    [MyApp.CounterReducer, MyApp.AuditReducer, MyApp.PermissionsReducer]
  end
end

defmodule MyApp.GuestSessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init_state(_args), do: %{}

  @impl true
  def combined_reducers do
    # Guest sessions get minimal state
    [MyApp.CounterReducer, MyApp.PreferencesReducer]
  end
end
```

**Key Benefit**: `CounterReducer` is defined once but reused across admin, guest, and regular sessions. Each session type composes different reducers to match its needs.

#### Using the Redux Store

```elixir
# In your controller:
{:ok, _pid} = Phoenix.SessionProcess.start_session(session_id, module: MyApp.SessionProcess)

# Dispatch actions (MUST use binary types)
:ok = Phoenix.SessionProcess.dispatch(session_id, "counter.increment")
:ok = Phoenix.SessionProcess.dispatch(session_id, "counter.set", 10)

# Async dispatch (convenience - automatically adds async: true)
:ok = Phoenix.SessionProcess.dispatch_async(session_id, "counter.increment")

# Equivalent to:
# :ok = Phoenix.SessionProcess.dispatch(session_id, "counter.increment", nil, async: true)

# Get state (state is namespaced by reducer)
state = Phoenix.SessionProcess.get_state(session_id)
# => %{counter: %{count: 11}}

# Use selectors
count = Phoenix.SessionProcess.get_state(session_id, fn s -> s.counter.count end)

# Server-side selection (more efficient for large states)
count = Phoenix.SessionProcess.select_state(session_id, fn s -> s.counter.count end)

# Subscribe to state changes
{:ok, sub_id} = Phoenix.SessionProcess.subscribe(
  session_id,
  fn state -> state.counter.count end,  # Selector function
  :count_changed,                        # Event name
  self()                                 # Subscriber PID (optional)
)

# Receive notifications when count changes
receive do
  {:count_changed, new_count} -> IO.inspect(new_count, label: "Count")
end

# Unsubscribe
:ok = Phoenix.SessionProcess.unsubscribe(session_id, sub_id)
```

#### LiveView with Redux Store API

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess

  def mount(_params, %{"session_id" => session_id}, socket) do
    # Subscribe to user state
    {:ok, _sub_id} = SessionProcess.subscribe(
      session_id,
      fn state -> state.user end,
      :user_changed,
      self()
    )

    # Get initial state
    state = SessionProcess.get_state(session_id)

    {:ok, assign(socket, session_id: session_id, state: state)}
  end

  # Receive state updates
  def handle_info({:user_changed, user}, socket) do
    {:noreply, assign(socket, user: user)}
  end

  # Dispatch actions
  def handle_event("increment", _params, socket) do
    SessionProcess.dispatch(socket.assigns.session_id, "increment", nil, async: true)
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    # Subscriptions are automatically cleaned up via process monitoring
    :ok
  end
end
```

**Benefits of Reusable Reducers:**
- **Write Once, Use Everywhere**: Define state logic once, compose across session types
- **Modular State Management**: Each reducer manages one concern (cart, user, preferences)
- **Easy Testing**: Test reducers independently without session overhead
- **Compile-Time Safety**: Type validation for reducer structure and action types
- **Familiar Patterns**: Redux architecture developers already understand
- **Zero Boilerplate**: No Redux struct to manage, SessionProcess IS the store

---

## API Reference

### Starting Sessions

```elixir
# Start with default module
{:ok, pid} = Phoenix.SessionProcess.start_session("session_123")

# Start with custom module
{:ok, pid} = Phoenix.SessionProcess.start_session("session_123", module: MyApp.CustomProcess)

# Start with custom module and arguments
{:ok, pid} = Phoenix.SessionProcess.start_session("session_123",
  module: MyApp.CustomProcess,
  args: %{user_id: 456})

# Start with default module but custom arguments
{:ok, pid} = Phoenix.SessionProcess.start_session("session_123", args: %{debug: true})
```

### Communication

```elixir
# Check if session exists
Phoenix.SessionProcess.started?("session_123")

# Call the session process
{:ok, user} = Phoenix.SessionProcess.call("session_123", :get_user)

# Cast to the session process
:ok = Phoenix.SessionProcess.cast("session_123", {:set_user, user})

# Terminate session
:ok = Phoenix.SessionProcess.terminate("session_123")

# Reset session TTL (extend session lifetime)
:ok = Phoenix.SessionProcess.touch("session_123")

# List all sessions
sessions = Phoenix.SessionProcess.list_session()

# Get memory and performance statistics
stats = Phoenix.SessionProcess.session_stats()
# Returns: %{total_memory: ..., session_count: ..., process_info: [...]}
```

### Session Process Helpers

Access session information from within your process:

```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init(_init_arg) do
    # Get the current session ID
    session_id = get_session_id()
    {:ok, %{session_id: session_id, data: %{}}}
  end

  def get_current_session_id() do
    get_session_id()
  end
end
```

### Redux Store API (v1.0.0)

The built-in Redux Store API provides state management with reducers defined using the `:reducer` macro:

```elixir
# See "Redux Store API (v1.0.0)" section above for complete examples

# Dispatch actions (MUST use binary types)
:ok = Phoenix.SessionProcess.dispatch(session_id, "counter.increment")

# Async dispatch (convenience alias)
:ok = Phoenix.SessionProcess.dispatch_async(
  session_id,
  "user.set",
  %{id: 123}
)

# Get current state after dispatch
state = Phoenix.SessionProcess.get_state(session_id)

# Get state with selector (client-side)
user = Phoenix.SessionProcess.get_state(session_id, fn state -> state.user end)

# Server-side selection (more efficient for large states)
user = Phoenix.SessionProcess.select_state(session_id, fn state -> state.user end)

# Subscribe to state changes (with selector)
{:ok, sub_id} = Phoenix.SessionProcess.subscribe(
  session_id,
  fn state -> state.user end,  # Only notified when user changes
  :user_changed,               # Event name for messages
  self()                       # Subscriber PID
)

# Receive notifications
receive do
  {:user_changed, user} -> IO.inspect(user, label: "User changed")
end

# Unsubscribe
:ok = Phoenix.SessionProcess.unsubscribe(session_id, sub_id)
```

**Key Features:**
- **Dispatch actions**: Synchronous or asynchronous state updates
- **Selectors**: Subscribe to specific state slices with change detection
- **Process monitoring**: Automatic subscription cleanup
- **Immediate delivery**: Subscribers receive current state on subscribe
- **Reducers**: Composable state transformation functions

### Advanced Usage

#### Rate Limiting
The library includes built-in rate limiting to prevent session abuse:

```elixir
# Configure rate limiting (100 sessions per minute by default)
config :phoenix_session_process,
  rate_limit: 200,  # 200 sessions per minute
  max_sessions: 20_000  # Maximum concurrent sessions
```

#### Custom Session State
Store complex data structures and implement custom logic:

```elixir
defmodule MyApp.ComplexSessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init(_init_arg) do
    {:ok, %{
      user: nil,
      shopping_cart: [],
      preferences: %{},
      activity_log: []
    }}
  end

  @impl true
  def handle_cast({:add_to_cart, item}, state) do
    new_cart = [item | state.shopping_cart]
    new_state = %{state | shopping_cart: new_cart}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_cart_total, _from, state) do
    total = state.shopping_cart
      |> Enum.map(& &1.price)
      |> Enum.sum()
    {:reply, total, state}
  end
end
```

## State Management

Phoenix.SessionProcess uses standard GenServer state management. For 95% of use cases, this is all you need:

### Standard GenServer State (Recommended)

Use standard GenServer callbacks for full control over state management:

```elixir
defmodule MyApp.BasicSessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init(_init_arg) do
    {:ok, %{user_id: nil, data: %{}, timestamps: []}}
  end

  @impl true
  def handle_call(:get_user, _from, state) do
    {:reply, state.user_id, state}
  end

  @impl true
  def handle_cast({:set_user, user_id}, state) do
    {:noreply, %{state | user_id: user_id}}
  end

  @impl true
  def handle_cast({:add_data, key, value}, state) do
    new_data = Map.put(state.data, key, value)
    {:noreply, %{state | data: new_data}}
  end
end
```

This is idiomatic Elixir and gives you full control over your state transitions.




## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `:session_process` | `Phoenix.SessionProcess.DefaultSessionProcess` | Default session module |
| `:max_sessions` | `10_000` | Maximum concurrent sessions |
| `:session_ttl` | `3_600_000` | Session TTL in milliseconds |
| `:rate_limit` | `100` | Sessions per minute limit |
| `:unmatched_action_handler` | `:log` | How to handle unmatched actions (`:log`, `:warn`, `:silent`, or custom function) |

## Telemetry and Monitoring

The library emits comprehensive telemetry events for monitoring and debugging:

### Session Lifecycle Events
- `[:phoenix, :session_process, :start]` - When a session starts
- `[:phoenix, :session_process, :stop]` - When a session stops
- `[:phoenix, :session_process, :start_error]` - When session start fails

### Communication Events
- `[:phoenix, :session_process, :call]` - When a call is made to a session
- `[:phoenix, :session_process, :cast]` - When a cast is made to a session
- `[:phoenix, :session_process, :communication_error]` - When communication fails

### Cleanup Events
- `[:phoenix, :session_process, :cleanup]` - When a session is cleaned up
- `[:phoenix, :session_process, :cleanup_error]` - When cleanup fails


### Example Telemetry Setup

```elixir
# Attach telemetry handlers
:telemetry.attach_many("session-handler", [
  [:phoenix, :session_process, :start],
  [:phoenix, :session_process, :stop]
], fn event, measurements, meta, _ ->
  Logger.info("Session event: #{inspect(event)} #{inspect(meta)}")
end, nil)

# Monitor session performance
:telemetry.attach("session-performance", [:phoenix, :session_process, :call], fn
  _, %{duration: duration}, %{session_id: session_id}, _ ->
    if duration > 1_000_000 do  # > 1ms
      Logger.warn("Slow session call for #{session_id}: #{duration}µs")
    end
end, nil)
```

## Error Handling

The library provides detailed error responses with the `Phoenix.SessionProcess.Error` module:

### Error Types
- `{:error, {:invalid_session_id, session_id}}` - Invalid session ID format
- `{:error, {:session_limit_reached, max_sessions}}` - Maximum sessions exceeded
- `{:error, {:session_not_found, session_id}}` - Session doesn't exist
- `{:error, {:process_not_found, session_id}}` - Process not found
- `{:error, {:timeout, timeout}}` - Operation timed out
- `{:error, {:call_failed, {module, function, args, reason}}}` - Call operation failed
- `{:error, {:cast_failed, {module, function, args, reason}}}` - Cast operation failed

### Error Handling Examples

```elixir
case Phoenix.SessionProcess.start_session(session_id) do
  {:ok, pid} ->
    # Session started successfully
    {:ok, pid}

  {:error, {:invalid_session_id, id}} ->
    Logger.error("Invalid session ID: #{id}")
    {:error, :invalid_session}

  {:error, {:session_limit_reached, max}} ->
    Logger.warn("Session limit reached: #{max}")
    {:error, :too_many_sessions}

  {:error, reason} ->
    Logger.error("Failed to start session: #{inspect(reason)}")
    {:error, :session_start_failed}
end
```

### Human-Readable Error Messages

Use `Phoenix.SessionProcess.Error.message/1` to get human-readable error messages:

```elixir
{:error, error} = Phoenix.SessionProcess.start_session("invalid@session")
Phoenix.SessionProcess.Error.message(error)
# Returns: "Invalid session ID format: \"invalid@session\""
```

## Testing

The library includes comprehensive tests. Run with:

```bash
mix test
```

## Benchmarking

Measure the performance of the library with built-in benchmarks:

### Quick Benchmark (5-10 seconds)
```bash
mix run bench/simple_bench.exs
```

### Comprehensive Benchmark (30-60 seconds)
```bash
mix run bench/session_benchmark.exs
```

### Expected Performance
- **Session Creation**: 10,000+ sessions/sec
- **Session Cleanup**: 20,000+ sessions/sec
- **Memory Usage**: ~10KB per session
- **Registry Lookups**: 100,000+ lookups/sec

See `bench/README.md` for detailed benchmarking guide and customization options.

### Development Setup

1. Fork the repository
2. Install dependencies: `mix deps.get`
3. Run tests: `mix test`
4. Run benchmarks: `mix run bench/simple_bench.exs`

The project uses `devenv` for development environment management. After installation, run `devenv shell` to enter the development environment.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes and version history.

## License

[MIT License](LICENSE)

## Credits

Created by [Jonathan Gao](https://github.com/gsmlg-dev)

## Related Projects

- [Phoenix LiveView](https://hex.pm/packages/phoenix_live_view) - Real-time user experiences
- [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html) - Real-time communication