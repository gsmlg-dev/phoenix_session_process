# Phoenix.SessionProcess

Create a process for each user session, all user requests go through this process. This provides session isolation, state management, and automatic cleanup with TTL support.

* [Github Repo](https://github.com/gsmlg-dev/phoenix_session_process)

## Features

- **Session Isolation**: Each user session runs in its own GenServer process
- **Automatic Cleanup**: TTL-based automatic session cleanup
- **Configuration Management**: Configurable TTL, session limits, and rate limiting
- **LiveView Integration**: Built-in support for monitoring LiveView processes
- **Extensible**: Custom session process modules with full GenServer support
- **Validation**: Session ID validation and concurrent session limits

## Installation

Add `phoenix_session_process` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_session_process, "~> 0.4.0"}
  ]
end
```

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

### With LiveView Integration

Create a session process that monitors LiveView processes:

```elixir
defmodule MyApp.SessionProcessWithLiveView do
  use Phoenix.SessionProcess, :process_link

  @impl true
  def init(_init_arg) do
    {:ok, %{user: nil, live_views: []}}
  end

  @impl true
  def handle_call(:get_user, _from, state) do
    {:reply, state.user, state}
  end

  @impl true
  def handle_cast({:set_user, user}, state) do
    {:noreply, %{state | user: user}}
  end
end
```

In your LiveView:

```elixir
defmodule MyAppWeb.UserLive do
  use MyAppWeb, :live_view

  def mount(_params, %{"session_id" => session_id} = _session, socket) do
    Phoenix.SessionProcess.cast(session_id, {:monitor, self()})
    {:ok, assign(socket, session_id: session_id)}
  end

  def handle_info(:session_expired, socket) do
    {:noreply, redirect(socket, to: "/login")}
  end
end
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

Inside your session process, use:

```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  def get_session_id() do
    # Returns the session ID for this process
    get_session_id()
  end
end
```

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

## License

[MIT License](LICENSE)