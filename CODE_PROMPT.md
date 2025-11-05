# Phoenix.SessionProcess - Code Prompt for Claude Code

This prompt helps Claude Code assist with Phoenix.SessionProcess, an Elixir library that enables **reusable, composable reducers** for managing user session state in Phoenix applications.

## Quick Reference

**Package**: `phoenix_session_process` v1.0.0
**Hex**: https://hex.pm/packages/phoenix_session_process
**Docs**: https://hexdocs.pm/phoenix_session_process/
**Requirements**: Elixir 1.14+, OTP 24+, Phoenix 1.6+

**Core Value**: Write state management logic once as reducers, then compose and reuse them across different session types.

## Core Concepts

### 1. Reusable Reducers - Primary Motivation
The library's main purpose is to enable **reusable reducer patterns** for session state management:

- **Define Once**: Write a reducer (e.g., CartReducer, UserReducer) one time
- **Use Everywhere**: Compose the same reducer in multiple session types (guest, user, admin)
- **Modular Logic**: Each reducer manages one concern (cart, authentication, preferences)
- **True Reusability**: A CartReducer works the same in guest and user sessions

Example:
```elixir
# Define once
defmodule MyApp.CartReducer do
  use Phoenix.SessionProcess, :reducer
  @name :cart
  # ... cart logic
end

# Use in multiple session types
defmodule MyApp.UserSession do
  def combined_reducers, do: [MyApp.CartReducer, MyApp.UserReducer]
end

defmodule MyApp.GuestSession do
  def combined_reducers, do: [MyApp.CartReducer]  # Reuse CartReducer
end
```

### 2. Session-Per-Process Architecture
Each user session runs in its own GenServer process, providing complete isolation and dedicated state management without external dependencies (no Redis, no database).

### 3. Redux Store Integration (v1.0.0)
SessionProcess **IS** the Redux store. No separate Redux struct needed. All state management flows through:
- **Actions**: Dispatched with `dispatch/4` - action types MUST be binary strings
- **Reducers**: Defined with `:reducer` macro - names MUST be atoms
- **Subscriptions**: Selector-based state change notifications
- **State**: Namespaced by reducer name

### 3. Key Constraints
- ✅ Action types: MUST be binary strings (e.g., `"increment"`, `"user.set"`)
- ✅ Reducer names: MUST be atoms (e.g., `:counter`, `:user`)
- ✅ Action prefix: MUST be binary, nil, or "" (e.g., `"counter"`, `nil`)
- ✅ dispatch/4 returns: `:ok` (not `{:ok, state}`)
- ✅ get_state/1 returns: state directly (not `{:ok, state}`)
- ✅ handle_async/3 returns: cancellation callback function `(() -> any())`

## Common Tasks

### Task 1: Initial Setup

**Add to mix.exs:**
```elixir
def deps do
  [
    {:phoenix_session_process, "~> 1.0"}
  ]
end
```

**Add to supervision tree (lib/my_app/application.ex):**
```elixir
def start(_type, _args) do
  children = [
    # ... other children
    {Phoenix.SessionProcess, []},
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

**Add plug to router (lib/my_app_web/router.ex):**
```elixir
pipeline :browser do
  plug :fetch_session
  plug Phoenix.SessionProcess.SessionId  # MUST be after :fetch_session
  # ... other plugs
end
```

**Configure (config/config.exs):**
```elixir
config :phoenix_session_process,
  session_process: MyApp.SessionProcess,
  max_sessions: 10_000,
  session_ttl: 3_600_000,  # 1 hour in milliseconds
  rate_limit: 100,
  unmatched_action_handler: :log  # :log | :warn | :silent | function
```

### Task 2: Define Reducers

**Counter reducer example:**
```elixir
defmodule MyApp.CounterReducer do
  use Phoenix.SessionProcess, :reducer

  @name :counter  # MUST be atom
  @action_prefix "counter"  # MUST be binary or nil

  @impl true
  def init_state do
    %{count: 0}
  end

  @impl true
  def handle_action(action, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "increment"} ->
        %{state | count: state.count + 1}

      %Action{type: "decrement"} ->
        %{state | count: state.count - 1}

      %Action{type: "set", payload: value} ->
        %{state | count: value}

      _ ->
        # Delegate to default handler
        handle_unmatched_action(action, state)
    end
  end

  # Optional: Handle async actions
  @impl true
  def handle_async(action, dispatch, state) do
    alias Phoenix.SessionProcess.Action

    case action do
      %Action{type: "fetch_remote", payload: url} ->
        task = Task.async(fn ->
          value = HTTPClient.get(url)
          # dispatch signature: dispatch(type, payload \\ nil, meta \\ [])
          dispatch.("set", value)
        end)

        # MUST return cancellation callback
        fn -> Task.shutdown(task, :brutal_kill) end

      _ ->
        handle_unmatched_async(action, dispatch, state)
    end
  end
end
```

### Task 3: Define Session Process

```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init_state(_args) do
    %{}  # Initial app state (reducers add their slices)
  end

  @impl true
  def combined_reducers do
    [
      MyApp.CounterReducer,
      MyApp.UserReducer,
      # Can also specify custom names:
      # {:custom_name, MyApp.SomeReducer},
      # {:another, MyApp.AnotherReducer, "action_prefix"}
    ]
  end
end
```

### Task 4: Use in Controllers

```elixir
defmodule MyAppWeb.PageController do
  use MyAppWeb, :controller
  alias Phoenix.SessionProcess

  def index(conn, _params) do
    session_id = get_session(conn, :session_id)

    # Start session
    {:ok, _pid} = SessionProcess.start_session(session_id)

    # Dispatch actions (MUST use binary types)
    :ok = SessionProcess.dispatch(session_id, "counter.increment")
    :ok = SessionProcess.dispatch(session_id, "user.set", %{id: 1, name: "Alice"})

    # Async dispatch (convenience)
    :ok = SessionProcess.dispatch_async(session_id, "counter.fetch_remote", "http://api.example.com/count")

    # Get state
    state = SessionProcess.get_state(session_id)
    # => %{counter: %{count: 1}, user: %{id: 1, name: "Alice"}}

    # Get state with selector (client-side)
    count = SessionProcess.get_state(session_id, fn s -> s.counter.count end)

    # Server-side selection (more efficient for large states)
    count = SessionProcess.select_state(session_id, fn s -> s.counter.count end)

    render(conn, "index.html", state: state, count: count)
  end
end
```

### Task 5: Start Sessions (in Router Hook or Login)

**Option A: Start in Router Hook**
```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  alias Phoenix.SessionProcess

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug Phoenix.SessionProcess.SessionId
    plug :ensure_session_process
    # ... other plugs
  end

  defp ensure_session_process(conn, _opts) do
    session_id = get_session(conn, :session_id)

    case SessionProcess.start_session(session_id) do
      {:ok, _pid} -> conn
      {:error, {:already_started, _pid}} -> conn
      {:error, reason} ->
        conn
        |> put_flash(:error, "Session unavailable")
        |> redirect(to: "/error")
        |> halt()
    end
  end
end
```

**Option B: Start at Login**
```elixir
defmodule MyAppWeb.AuthController do
  use MyAppWeb, :controller
  alias Phoenix.SessionProcess

  def login(conn, %{"user" => user_params}) do
    with {:ok, user} <- MyApp.Accounts.authenticate(user_params),
         session_id <- get_session(conn, :session_id),
         {:ok, _pid} <- SessionProcess.start_session(session_id) do

      # Initialize user state
      :ok = SessionProcess.dispatch(session_id, "user.set", user)

      conn
      |> put_flash(:info, "Logged in successfully")
      |> redirect(to: "/dashboard")
    else
      {:error, _} ->
        conn
        |> put_flash(:error, "Invalid credentials")
        |> render("login.html")
    end
  end
end
```

### Task 6: LiveView Integration

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess

  def mount(_params, %{"session_id" => session_id}, socket) do
    # Session should already be started (via router hook or login)
    # Just verify it exists
    if SessionProcess.started?(session_id) do
      # Subscribe to state changes with selector
      {:ok, sub_id} = SessionProcess.subscribe(
        session_id,
        fn state -> state.counter.count end,  # Selector
        :count_changed,  # Event name
        self()  # Subscriber PID (defaults to self())
      )

      # Get initial state
      count = SessionProcess.get_state(session_id, fn s -> s.counter.count end)

      {:ok, assign(socket, session_id: session_id, sub_id: sub_id, count: count)}
    else
      # Session not found - redirect to login or show error
      {:ok, push_redirect(socket, to: "/login")}
    end
  end

  # Handle subscription messages
  def handle_info({:count_changed, new_count}, socket) do
    {:noreply, assign(socket, count: new_count)}
  end

  # Dispatch actions from events
  def handle_event("increment", _params, socket) do
    :ok = SessionProcess.dispatch(socket.assigns.session_id, "counter.increment")
    {:noreply, socket}
  end

  def handle_event("decrement", _params, socket) do
    # Async dispatch
    :ok = SessionProcess.dispatch_async(socket.assigns.session_id, "counter.decrement")
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    # Cleanup is automatic via process monitoring, but can explicitly unsubscribe
    if sub_id = socket.assigns[:sub_id] do
      SessionProcess.unsubscribe(socket.assigns.session_id, sub_id)
    end
    :ok
  end
end
```

### Task 6: Testing

```elixir
defmodule MyAppWeb.PageControllerTest do
  use MyAppWeb.ConnCase
  alias Phoenix.SessionProcess

  test "session state management", %{conn: conn} do
    # Get session ID from conn
    conn = get(conn, "/")
    session_id = get_session(conn, :session_id)

    # Verify session started
    assert SessionProcess.started?(session_id)

    # Test state updates
    :ok = SessionProcess.dispatch(session_id, "counter.increment")
    state = SessionProcess.get_state(session_id)
    assert state.counter.count == 1

    # Test async dispatch
    :ok = SessionProcess.dispatch_async(session_id, "counter.increment")
    Process.sleep(10)  # Allow async to complete
    state = SessionProcess.get_state(session_id)
    assert state.counter.count == 2

    # Cleanup
    :ok = SessionProcess.terminate(session_id)
    refute SessionProcess.started?(session_id)
  end
end
```

## API Reference

### Session Management
- `start_session(session_id)` - Start with default module
- `start_session(session_id, module: Module)` - Start with custom module
- `start_session(session_id, args: term)` - Start with default module and custom args
- `start_session(session_id, module: Module, args: term)` - Start with custom module and args
- `started?(session_id)` - Check if session exists
- `terminate(session_id)` - Stop session
- `touch(session_id)` - Reset session TTL (extend lifetime)
- `list_session()` - List all sessions
- `session_stats()` - Get memory and performance statistics

### Redux Store API
- `dispatch(session_id, type, payload \\ nil, meta \\ [])` - Dispatch action (returns `:ok`)
- `dispatch_async(session_id, type, payload \\ nil, meta \\ [])` - Async dispatch (returns `:ok`)
- `get_state(session_id)` - Get full state (returns state directly)
- `get_state(session_id, selector)` - Get state with client-side selector
- `select_state(session_id, selector)` - Apply selector on server-side (more efficient)
- `subscribe(session_id, selector, event_name, pid \\ self())` - Subscribe to changes (returns `{:ok, sub_id}`)
- `unsubscribe(session_id, sub_id)` - Remove subscription (returns `:ok`)

### Communication (Advanced)
- `call(session_id, message, timeout \\ 5000)` - Synchronous call to GenServer
- `cast(session_id, message)` - Asynchronous cast to GenServer

## Common Mistakes to Avoid

### ❌ WRONG: Using atom action types
```elixir
# DON'T DO THIS
SessionProcess.dispatch(session_id, :increment)  # ArgumentError!
```

### ✅ CORRECT: Use binary action types
```elixir
SessionProcess.dispatch(session_id, "increment")
```

---

### ❌ WRONG: Expecting tuple return from get_state
```elixir
# DON'T DO THIS
{:ok, state} = SessionProcess.get_state(session_id)  # Match error!
```

### ✅ CORRECT: get_state returns state directly
```elixir
state = SessionProcess.get_state(session_id)
```

---

### ❌ WRONG: Expecting tuple return from dispatch
```elixir
# DON'T DO THIS
{:ok, new_state} = SessionProcess.dispatch(session_id, "increment")  # Match error!
```

### ✅ CORRECT: dispatch returns :ok
```elixir
:ok = SessionProcess.dispatch(session_id, "increment")
```

---

### ❌ WRONG: String reducer name
```elixir
# DON'T DO THIS
defmodule MyApp.CounterReducer do
  use Phoenix.SessionProcess, :reducer
  @name "counter"  # Compile error!
end
```

### ✅ CORRECT: Atom reducer name
```elixir
defmodule MyApp.CounterReducer do
  use Phoenix.SessionProcess, :reducer
  @name :counter
end
```

---

### ❌ WRONG: handle_async returns state
```elixir
# DON'T DO THIS
def handle_async(action, dispatch, state) do
  Task.async(fn -> dispatch.("done") end)
  state  # Wrong return type!
end
```

### ✅ CORRECT: handle_async returns cancellation callback
```elixir
def handle_async(action, dispatch, state) do
  task = Task.async(fn -> dispatch.("done") end)
  fn -> Task.shutdown(task, :brutal_kill) end
end
```

---

### ❌ WRONG: Using attach_hook for subscriptions in LiveView
```elixir
# DON'T DO THIS
def mount(_params, %{"session_id" => session_id}, socket) do
  {:ok, sub_id} = SessionProcess.subscribe(session_id, selector, :event, self())
  socket = attach_hook(socket, :session, :handle_info, &handle_session/2)
  {:ok, socket}
end

defp handle_session({:event, data}, socket), do: {:cont, assign(socket, data: data)}
```

### ✅ CORRECT: Use handle_info directly
```elixir
def mount(_params, %{"session_id" => session_id}, socket) do
  {:ok, sub_id} = SessionProcess.subscribe(session_id, selector, :event, self())
  {:ok, assign(socket, sub_id: sub_id)}
end

def handle_info({:event, data}, socket) do
  {:noreply, assign(socket, data: data)}
end
```

## Best Practices

### 1. Action Naming Conventions
Use namespaced action types with the action prefix:
```elixir
# Reducer with prefix "user"
@action_prefix "user"

# Actions: "user.set", "user.update", "user.delete"
dispatch(session_id, "user.set", user_data)
dispatch(session_id, "user.update", changes)
```

The prefix is stripped automatically before reaching `handle_action/2`:
```elixir
def handle_action(action, state) do
  case action do
    %Action{type: "set"} -> # Matches "user.set"
    %Action{type: "update"} -> # Matches "user.update"
  end
end
```

### 2. Start Sessions Early in Request Lifecycle
**IMPORTANT**: Sessions should be started in router hooks or login controllers, NOT in LiveView mount.

```elixir
# ✅ GOOD: Start in router hook
pipeline :browser do
  plug :fetch_session
  plug Phoenix.SessionProcess.SessionId
  plug :ensure_session_process  # Start session here
end

# ✅ GOOD: Start at login
def login(conn, params) do
  with {:ok, user} <- authenticate(params),
       session_id <- get_session(conn, :session_id),
       {:ok, _pid} <- SessionProcess.start_session(session_id) do
    # Session ready for use
  end
end

# ❌ BAD: Starting in LiveView mount
def mount(_params, %{"session_id" => id}, socket) do
  SessionProcess.start_session(id)  # DON'T DO THIS!
  # LiveView is too late - start earlier
end
```

### 3. Use Selectors for Efficient Subscriptions
Only subscribe to the state you need:
```elixir
# ✅ GOOD: Subscribe to specific value
{:ok, _} = SessionProcess.subscribe(
  session_id,
  fn state -> state.user.id end,  # Only notified when user.id changes
  :user_id_changed,
  self()
)

# ❌ BAD: Subscribe to entire state
{:ok, _} = SessionProcess.subscribe(
  session_id,
  fn state -> state end,  # Notified on ANY state change
  :state_changed,
  self()
)
```

### 4. Prefer select_state for Large States
When state is large, use `select_state/2` for server-side selection:
```elixir
# ✅ GOOD: Server-side selection (only selected value transferred)
user = SessionProcess.select_state(session_id, fn s -> s.user end)

# ❌ LESS EFFICIENT: Client-side selection (full state transferred)
user = SessionProcess.get_state(session_id, fn s -> s.user end)
```

### 5. Handle Unmatched Actions
Override `handle_unmatched_action/2` for debugging or custom behavior:
```elixir
@impl true
def handle_unmatched_action(action, state) do
  # Log unexpected actions for debugging
  require Logger
  Logger.warning("Unmatched action in #{__MODULE__}: #{inspect(action)}")

  # Or track metrics
  MyApp.Metrics.increment("unmatched_actions", reducer: __MODULE__)

  state  # Return state unchanged
end
```

Or configure globally:
```elixir
config :phoenix_session_process,
  unmatched_action_handler: :warn  # :log | :warn | :silent | function
```

### 6. Session Lifecycle Management
Always handle session start errors:
```elixir
case SessionProcess.start_session(session_id) do
  {:ok, _pid} ->
    # Session started successfully
    :ok

  {:error, {:already_started, _pid}} ->
    # Session already exists - this is usually fine
    :ok

  {:error, {:session_limit_reached, max}} ->
    # Too many sessions - inform user or queue
    {:error, :service_busy}

  {:error, reason} ->
    # Other error - log and handle
    Logger.error("Session start failed: #{inspect(reason)}")
    {:error, :session_unavailable}
end
```

### 7. Testing Async Actions
Allow time for async actions to complete:
```elixir
test "async action updates state" do
  :ok = SessionProcess.dispatch_async(session_id, "fetch_data")

  # Wait for async to complete
  Process.sleep(50)

  # Or use explicit synchronization
  assert_receive {:data_loaded, _}, 1000

  state = SessionProcess.get_state(session_id)
  assert state.data != nil
end
```

## Performance Considerations

### Expected Performance (per the benchmarks)
- **Session Creation**: 10,000+ sessions/sec
- **Memory Usage**: ~10KB per session
- **Registry Lookups**: 100,000+ lookups/sec
- **Dispatch Operations**: Sub-microsecond for simple reducers

### Optimization Tips
1. Use `select_state/2` for large states
2. Design selectors to return minimal data
3. Use action prefixes to limit reducer invocations
4. Configure appropriate `session_ttl` for your use case
5. Monitor via telemetry events

## Telemetry Events

The library emits these telemetry events:
- `[:phoenix, :session_process, :start]` - Session starts
- `[:phoenix, :session_process, :stop]` - Session stops
- `[:phoenix, :session_process, :start_error]` - Start failures
- `[:phoenix, :session_process, :call]` - Call operations
- `[:phoenix, :session_process, :cast]` - Cast operations
- `[:phoenix, :session_process, :communication_error]` - Communication failures
- `[:phoenix, :session_process, :cleanup]` - Session cleanup
- `[:phoenix, :session_process, :cleanup_error]` - Cleanup failures

## When to Use This Library

### ✅ Good Use Cases
- **Need reusable state logic**: Same reducer works for guest, user, and admin sessions
- **Complex session state**: Multiple concerns (cart, auth, preferences) managed by separate reducers
- **Phoenix LiveView applications**: Per-user state with reactive updates
- **Want Redux patterns in Elixir**: Familiar architecture, no external dependencies
- **Multiple session types**: Different user roles need different state combinations
- **Testing reducer logic**: Test state management independently of sessions
- **High-performance needs**: 10,000+ concurrent users with isolated state

### ❌ When NOT to Use
- Stateless APIs that don't need session state
- Applications requiring session persistence across restarts (use database)
- Shared state between users (use PubSub or other mechanisms)
- Very short-lived requests (overhead not justified)
- Simple session needs (just use Phoenix.Session plug)

## Troubleshooting

### Issue: Session not found
```elixir
{:error, {:session_not_found, session_id}}
```
**Solution**: Ensure session is started before calling dispatch/get_state/subscribe

### Issue: Invalid session ID
```elixir
{:error, {:invalid_session_id, id}}
```
**Solution**: Verify SessionId plug is added after :fetch_session in router

### Issue: Actions not triggering reducer
**Solution**: Check action prefix matches. If prefix is "counter", dispatch "counter.increment" not just "increment"

### Issue: Unmatched actions logged constantly
**Solution**: Either add action prefix to limit routing, or configure `unmatched_action_handler: :silent`

### Issue: Subscription not receiving updates
**Solution**: Verify selector is comparing correctly. Selector must return different value for notification to be sent.

## Additional Resources

- **Hex Docs**: https://hexdocs.pm/phoenix_session_process/
- **Source Code**: https://github.com/gsmlg-dev/phoenix_session_process
- **Benchmarks**: Run `mix run bench/session_benchmark.exs`
- **Examples**: See `test/` directory for comprehensive examples

## Summary for Claude Code

When helping users with Phoenix.SessionProcess:

1. **Session lifecycle**: Start sessions in router hooks or login controllers, NOT in LiveView mount
2. **Always verify**: Action types are binary strings, reducer names are atoms
3. **Correct returns**: `dispatch/4` returns `:ok`, `get_state/1` returns state directly
4. **LiveView pattern**: Use `handle_info/2` directly, not `attach_hook/3`
5. **Async callbacks**: `handle_async/3` must return cancellation function
6. **Action prefixes**: Automatically stripped before reaching reducers
7. **Subscriptions**: Use selectors for efficient updates, cleanup is automatic via monitoring
8. **Testing**: Allow time for async actions to complete

This library provides **reusable, composable reducers** for session state management. Define your state logic once, compose it across different session types, and leverage Redux patterns in a high-performance session-per-process architecture - perfect for Phoenix LiveView applications requiring modular, isolated user state without external dependencies.
