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
    {:phoenix_session_process, "~> 0.4.0"}
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
    {Phoenix.SessionProcess.Supervisor, []}
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
    {:ok, _pid} = Phoenix.SessionProcess.start(session_id)
    
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
  pubsub: MyApp.PubSub                   # PubSub module for LiveView integration
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

### With LiveView Integration

Phoenix.SessionProcess provides PubSub-based LiveView integration for real-time state synchronization.

#### Session Process with Broadcasting

```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init(_init_arg) do
    {:ok, %{user: nil, count: 0}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_cast({:set_user, user}, state) do
    new_state = %{state | user: user}
    # Broadcast state changes to all subscribers
    broadcast_state_change(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:increment, state) do
    new_state = %{state | count: state.count + 1}
    broadcast_state_change(new_state)
    {:noreply, new_state}
  end
end
```

#### LiveView with Session Integration

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess.LiveView, as: SessionLV

  def mount(_params, %{"session_id" => session_id}, socket) do
    # Subscribe to session state and get initial state
    case SessionLV.mount_session(socket, session_id, MyApp.PubSub) do
      {:ok, socket, state} ->
        {:ok, assign(socket, state: state, session_id: session_id)}

      {:error, _reason} ->
        {:ok, redirect(socket, to: "/login")}
    end
  end

  # Automatically receive state updates
  def handle_info({:session_state_change, new_state}, socket) do
    {:noreply, assign(socket, state: new_state)}
  end

  # Send messages to session
  def handle_event("increment", _params, socket) do
    SessionLV.dispatch_async(socket.assigns.session_id, :increment)
    {:noreply, socket}
  end

  # Clean up subscription on terminate
  def terminate(_reason, socket) do
    SessionLV.unmount_session(socket)
    :ok
  end
end
```

#### Configuration for LiveView

Add PubSub module to your config:

```elixir
# config/config.exs
config :phoenix_session_process,
  pubsub: MyApp.PubSub  # Required for LiveView integration
```

## API Reference

### Starting Sessions

```elixir
# Start with default module
{:ok, pid} = Phoenix.SessionProcess.start("session_123")

# Start with custom module
{:ok, pid} = Phoenix.SessionProcess.start("session_123", MyApp.CustomProcess)

# Start with custom module and arguments
{:ok, pid} = Phoenix.SessionProcess.start("session_123", MyApp.CustomProcess, %{user_id: 456})
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

### Advanced: Redux-Style State (Optional)

For complex applications requiring audit trails or time-travel debugging, you can optionally use `Phoenix.SessionProcess.Redux`:

```elixir
defmodule MyApp.ReduxSessionProcess do
  use Phoenix.SessionProcess, :process
  alias Phoenix.SessionProcess.Redux

  @impl true
  def init(_init_arg) do
    initial_state = %{
      user: nil,
      preferences: %{},
      cart: [],
      activity_log: []
    }

    redux = Redux.init_state(initial_state, reducer: &reducer/2)
    {:ok, %{redux: redux}}
  end

  # Define reducer to handle all state changes
  def reducer(state, action) do
    case action do
      {:set_user, user} ->
        %{state | user: user}

      {:update_preferences, prefs} ->
        %{state | preferences: Map.merge(state.preferences, prefs)}

      {:add_to_cart, item} ->
        %{state | cart: [item | state.cart]}

      {:remove_from_cart, item_id} ->
        cart = Enum.reject(state.cart, &(&1.id == item_id))
        %{state | cart: cart}

      :clear_cart ->
        %{state | cart: []}

      {:log_activity, activity} ->
        log = [activity | state.activity_log]
        %{state | activity_log: log}

      :reset ->
        %{user: nil, preferences: %{}, cart: [], activity_log: []}

      _ ->
        state
    end
  end

  @impl true
  def handle_call(:get_state, _from, %{redux: redux} = state) do
    current_state = Redux.current_state(redux)
    {:reply, current_state, state}
  end

  @impl true
  def handle_call(:get_history, _from, %{redux: redux} = state) do
    history = Redux.history(redux)
    {:reply, history, state}
  end

  @impl true
  def handle_cast({:dispatch, action}, %{redux: redux} = state) do
    new_redux = Redux.dispatch(redux, action)
    {:noreply, %{state | redux: new_redux}}
  end
end

# Usage
Phoenix.SessionProcess.start("session_123", MyApp.ReduxSessionProcess)
Phoenix.SessionProcess.cast("session_123", {:dispatch, {:set_user, %{id: 1, name: "Alice"}}})
Phoenix.SessionProcess.cast("session_123", {:dispatch, {:add_to_cart, %{id: 101, name: "Widget", price: 29.99}}})

{:ok, state} = Phoenix.SessionProcess.call("session_123", :get_state)
{:ok, history} = Phoenix.SessionProcess.call("session_123", :get_history)
```

#### Redux with Subscriptions and Selectors

React to specific state changes with subscriptions and selectors:

```elixir
defmodule MyApp.ReactiveSession do
  use Phoenix.SessionProcess, :process
  alias Phoenix.SessionProcess.Redux
  alias Phoenix.SessionProcess.Redux.Selector

  @impl true
  def init(_init_arg) do
    redux = Redux.init_state(%{user: nil, cart: [], total: 0})

    # Subscribe to user changes
    redux =
      Redux.subscribe(redux, fn state -> state.user end, fn user ->
        IO.inspect(user, label: "User changed")
      end)

    # Subscribe with memoized selector for cart total
    cart_total_selector =
      Selector.create_selector(
        [fn state -> state.cart end],
        fn cart ->
          Enum.reduce(cart, 0, fn item, acc -> acc + item.price end)
        end
      )

    redux =
      Redux.subscribe(redux, cart_total_selector, fn total ->
        IO.inspect(total, label: "Cart total")
      end)

    {:ok, %{redux: redux}}
  end

  @impl true
  def handle_call({:dispatch, action}, _from, state) do
    new_redux = Redux.dispatch(state.redux, action, &reducer/2)
    {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
  end

  defp reducer(state, action) do
    case action do
      {:set_user, user} -> %{state | user: user}
      {:add_to_cart, item} -> %{state | cart: [item | state.cart]}
      {:clear_cart} -> %{state | cart: []}
      _ -> state
    end
  end
end
```

#### Redux with LiveView

Automatically update LiveView assigns from Redux state:

```elixir
defmodule MyAppWeb.ShoppingCartLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess.Redux.LiveView, as: ReduxLV
  alias Phoenix.SessionProcess.Redux.Selector

  def mount(_params, %{"session_id" => session_id}, socket) do
    if connected?(socket) do
      # Define selectors
      cart_count_selector = Selector.create_selector(
        [fn state -> state.cart end],
        fn cart -> length(cart) end
      )

      cart_total_selector = Selector.create_selector(
        [fn state -> state.cart end],
        fn cart -> Enum.reduce(cart, 0, &(&1.price + &2)) end
      )

      # Auto-subscribe to Redux changes
      socket =
        ReduxLV.assign_from_session(socket, session_id, %{
          user: fn state -> state.user end,
          cart_count: cart_count_selector,
          cart_total: cart_total_selector
        })

      {:ok, assign(socket, session_id: session_id)}
    else
      {:ok, assign(socket, session_id: session_id, user: nil, cart_count: 0, cart_total: 0)}
    end
  end

  # Handle automatic Redux assign updates
  def handle_info({:redux_assign_update, key, value}, socket) do
    {:noreply, ReduxLV.handle_assign_update(socket, key, value)}
  end

  def handle_event("add_item", %{"item" => item}, socket) do
    ReduxLV.dispatch_to_session(socket.assigns.session_id, {:add_to_cart, item})
    {:noreply, socket}
  end

  def render(assigns) do
    ~H\"\"\"
    <div>
      <h2>Welcome, <%= @user.name %></h2>
      <p>Cart: <%= @cart_count %> items</p>
      <p>Total: $<%= @cart_total %></p>
    </div>
    \"\"\"
  end
end
```

#### Redux with PubSub (Distributed)

Share state across nodes with Phoenix.PubSub:

```elixir
defmodule MyApp.DistributedSession do
  use Phoenix.SessionProcess, :process
  alias Phoenix.SessionProcess.Redux

  @impl true
  def init(arg) do
    session_id = Keyword.get(arg, :session_id)

    # Enable PubSub broadcasting
    redux =
      Redux.init_state(
        %{data: %{}},
        pubsub: MyApp.PubSub,
        pubsub_topic: "session:\#{session_id}"
      )

    {:ok, %{redux: redux}}
  end

  @impl true
  def handle_call({:dispatch, action}, _from, state) do
    # Dispatch automatically broadcasts via PubSub
    new_redux = Redux.dispatch(state.redux, action, &reducer/2)
    {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
  end

  defp reducer(state, action) do
    case action do
      {:update, data} -> %{state | data: Map.merge(state.data, data)}
      _ -> state
    end
  end
end

# Listen from any node
defmodule MyApp.RemoteListener do
  def listen(session_id) do
    Redux.subscribe_to_broadcasts(
      MyApp.PubSub,
      "session:\#{session_id}",
      fn %{action: action, state: state} ->
        IO.inspect({action, state}, label: "Remote state change")
      end
    )
  end
end
```

**Redux Features:**
- **Time-travel debugging** - Access complete action history
- **Middleware support** - Add logging, validation, side effects
- **Subscriptions** - React to specific state changes with callbacks
- **Selectors with memoization** - Efficient derived state computation
- **LiveView integration** - Automatic assign updates
- **Phoenix.PubSub support** - Distributed state notifications across nodes
- **State persistence** - Serialize and restore state
- **Predictable updates** - All changes through explicit actions
- **Comprehensive telemetry** - Monitor Redux operations

**Best for:** Complex applications, team collaboration, debugging requirements, state persistence needs, real-time reactive UIs.

### Comparison

| Feature | Basic GenServer | Agent State | Redux |
|---------|----------------|-------------|-------|
| Complexity | Low | Very Low | Medium |
| Performance | Excellent | Excellent | Good |
| Debugging | Manual | Manual | Built-in |
| Time-travel | No | No | Yes |
| Middleware | Manual | No | Yes |
| State History | No | No | Yes |
| Learning Curve | Low | Very Low | Medium |

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for detailed Redux migration guide and examples.

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

### Redux State Management Events
- `[:phoenix, :session_process, :redux, :dispatch]` - When a Redux action is dispatched
- `[:phoenix, :session_process, :redux, :subscribe]` - When a subscription is created
- `[:phoenix, :session_process, :redux, :unsubscribe]` - When a subscription is removed
- `[:phoenix, :session_process, :redux, :notification]` - When subscriptions are notified
- `[:phoenix, :session_process, :redux, :selector_cache_hit]` - When selector cache is hit
- `[:phoenix, :session_process, :redux, :selector_cache_miss]` - When selector cache misses
- `[:phoenix, :session_process, :redux, :pubsub_broadcast]` - When state is broadcast via PubSub
- `[:phoenix, :session_process, :redux, :pubsub_receive]` - When PubSub broadcast is received

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
case Phoenix.SessionProcess.start(session_id) do
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
{:error, error} = Phoenix.SessionProcess.start("invalid@session")
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
- [Phoenix PubSub](https://hex.pm/packages/phoenix_pubsub) - Distributed PubSub
- [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html) - Real-time communication