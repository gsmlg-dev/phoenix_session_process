# Phoenix.SessionProcess

[![Hex Version](https://img.shields.io/hexpm/v/phoenix_session_process.svg)](https://hex.pm/packages/phoenix_session_process)
[![Hex Docs](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/phoenix_session_process/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A powerful Phoenix library that creates a dedicated process for each user session. All user requests go through their dedicated session process, providing complete session isolation, robust state management, and automatic cleanup with TTL support.

## Why Phoenix.SessionProcess?

Traditional session management stores session data in external stores (Redis, database) or relies on plug-based state. **Phoenix.SessionProcess** takes a different approach by giving each user their own GenServer process, enabling:

- **Real-time session state** without external dependencies
- **Perfect session isolation** - no shared state between users
- **Built-in LiveView integration** for reactive UIs
- **Automatic memory management** with configurable TTL
- **Enterprise-grade performance** - 10,000+ sessions/second
- **Zero external dependencies** beyond core Phoenix/OTP

## Features

- **Session Isolation**: Each user session runs in its own GenServer process
- **Redux Store Integration**: Built-in Redux with actions, reducers, and selectors (NEW in v0.6.0)
- **Reactive Subscriptions**: Subscribe to state changes with selector-based change detection
- **Automatic Cleanup**: TTL-based automatic session cleanup and memory management
- **LiveView Integration**: Built-in support for monitoring LiveView processes
- **High Performance**: Optimized for 10,000+ concurrent sessions
- **Configuration Management**: Configurable TTL, session limits, and rate limiting
- **Extensible**: Custom session process modules with full GenServer support
- **Comprehensive Monitoring**: Built-in telemetry and performance metrics
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
    session_id = conn.assigns.session_id
    
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
  rate_limit: 100                        # Sessions per minute limit
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

### Redux Store API (v1.0.0)

Phoenix.SessionProcess includes built-in Redux functionality - **SessionProcess IS the Redux store**. Use the `:reducer` macro to define reducers with binary action types.

#### Defining Reducers

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

  def init_state(_args) do
    %{}
  end

  def combined_reducers do
    [MyApp.CounterReducer]
  end
end
```

#### Using the Redux Store

```elixir
# In your controller:
{:ok, _pid} = Phoenix.SessionProcess.start_session(session_id, MyApp.SessionProcess)

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
    {:ok, state} = SessionProcess.get_state(session_id)

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

**Benefits of the new API:**
- 70% less boilerplate code
- No Redux struct to manage
- Direct SessionProcess integration
- Automatic subscription cleanup
- Process-level selectors for efficient updates

---

## API Reference

### Starting Sessions

```elixir
# Start with default module
{:ok, pid} = Phoenix.SessionProcess.start_session("session_123")

# Start with custom module
{:ok, pid} = Phoenix.SessionProcess.start_session("session_123", MyApp.CustomProcess)

# Start with custom module and arguments
{:ok, pid} = Phoenix.SessionProcess.start_session("session_123", MyApp.CustomProcess, %{user_id: 456})
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

# List all sessions
sessions = Phoenix.SessionProcess.list_session()
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

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

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