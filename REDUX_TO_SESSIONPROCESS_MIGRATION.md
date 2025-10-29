# Migration Guide: Redux Module → SessionProcess Native Redux

## Overview

Phoenix.SessionProcess v0.6.0 introduces a major architectural simplification: **SessionProcess IS now the Redux store**. The separate `Redux` module is deprecated in favor of built-in Redux capabilities directly in SessionProcess.

## Why This Change?

### Before (Complex)
```elixir
# Redux was a nested struct requiring manual management
defmodule MyApp.SessionProcess do
  def init(_) do
    redux = Redux.init_state(%{count: 0})
    {:ok, %{redux: redux, other_data: ...}}
  end

  def handle_call({:dispatch, action}, _from, state) do
    new_redux = Redux.dispatch(state.redux, action, &reducer/2)
    {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
  end
end
```

### After (Simple)
```elixir
# SessionProcess manages Redux natively
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  def init(_) do
    {:ok, %{app_state: %{count: 0}}}
  end
end

# Usage
SessionProcess.dispatch(session_id, {:increment, 1})
```

**Benefits**:
- 70% less boilerplate
- Simpler mental model
- Natural GenServer patterns
- Better performance

## Quick Migration Checklist

- [ ] Update `init/1` to return `%{app_state: ...}` instead of `%{redux: ...}`
- [ ] Replace `Redux.dispatch` calls with `SessionProcess.dispatch`
- [ ] Replace `Redux.subscribe` calls with `SessionProcess.subscribe`
- [ ] Remove manual subscription handlers (now handled by macro)
- [ ] Update LiveView integration to use new API
- [ ] Remove `alias Phoenix.SessionProcess.Redux` lines
- [ ] Test thoroughly!

## Detailed Migration Steps

### Step 1: Update Session Process Init

#### Before
```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process
  alias Phoenix.SessionProcess.Redux

  @impl true
  def init(_init_arg) do
    redux = Redux.init_state(%{
      count: 0,
      user: nil,
      items: []
    })

    {:ok, %{redux: redux}}
  end
end
```

#### After
```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  @impl true
  def init(_init_arg) do
    # State is now app_state directly - Redux infrastructure is managed by macro
    {:ok, %{
      app_state: %{
        count: 0,
        user: nil,
        items: []
      }
    }}
  end

  # Optional: Use user_init for reducer registration
  def user_init(_arg) do
    session_id = get_session_id()
    Phoenix.SessionProcess.register_reducer(session_id, :main, &reducer/2)

    %{count: 0, user: nil, items: []}
  end

  defp reducer(state, {:increment, value}), do: %{state | count: state.count + value}
  defp reducer(state, {:set_user, user}), do: %{state | user: user}
  defp reducer(state, _), do: state
end
```

### Step 2: Replace Dispatch Calls

#### Before
```elixir
# In session process
def handle_call({:dispatch, action}, _from, state) do
  new_redux = Redux.dispatch(state.redux, action, &reducer/2)
  {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
end

# In controller
Phoenix.SessionProcess.call(session_id, {:dispatch, {:increment, 1}})
```

#### After
```elixir
# In session process
# Nothing needed! The :process macro handles dispatch automatically

# In controller
Phoenix.SessionProcess.dispatch(session_id, {:increment, 1})

# Or async
Phoenix.SessionProcess.dispatch(session_id, {:increment, 1}, async: true)
```

### Step 3: Update Subscriptions

#### Before
```elixir
# In session process
def handle_call({:subscribe, selector, pid, event}, _from, state) do
  {:ok, sub_id, new_redux} = Redux.subscribe(
    state.redux,
    selector,
    pid,
    event
  )
  {:reply, {:ok, sub_id}, %{state | redux: new_redux}}
end

# In LiveView
{:ok, sub_id} = Phoenix.SessionProcess.call(session_id, {
  :subscribe,
  fn state -> state.user end,
  self(),
  :user_changed
})
```

#### After
```elixir
# In session process
# Nothing needed! The :process macro handles subscriptions automatically

# In LiveView - much simpler!
{:ok, sub_id} = Phoenix.SessionProcess.subscribe(
  session_id,
  fn state -> state.user end,
  :user_changed
)

# Unsubscribe
:ok = Phoenix.SessionProcess.unsubscribe(session_id, sub_id)
```

### Step 4: Update LiveView Integration

#### Before
```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess.Redux.LiveView, as: ReduxLV

  def mount(_params, %{"session_id" => session_id}, socket) do
    socket = ReduxLV.subscribe_to_session(
      socket,
      session_id,
      fn state -> state.user end,
      fn user -> send(self(), {:user_changed, user}) end
    )

    {:ok, socket}
  end

  def handle_info({:user_changed, user}, socket) do
    {:noreply, assign(socket, :user, user)}
  end
end
```

#### After
```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess

  def mount(_params, %{"session_id" => session_id}, socket) do
    # Direct subscription with new API
    {:ok, sub_id} = SessionProcess.subscribe(
      session_id,
      fn state -> state.user end,
      :user_changed
    )

    socket = assign(socket, subscription_id: sub_id, session_id: session_id)
    {:ok, socket}
  end

  def handle_info({:user_changed, user}, socket) do
    {:noreply, assign(socket, :user, user)}
  end

  def terminate(_reason, socket) do
    if sub_id = socket.assigns[:subscription_id] do
      SessionProcess.unsubscribe(socket.assigns.session_id, sub_id)
    end
    :ok
  end
end
```

### Step 5: Update State Access

#### Before
```elixir
# Accessing nested Redux state
def handle_call(:get_count, _from, state) do
  count = Redux.get_state(state.redux).count
  {:reply, count, state}
end
```

#### After
```elixir
# Direct state access or use SessionProcess API
def handle_call(:get_count, _from, state) do
  count = state.app_state.count
  {:reply, count, state}
end

# Or from outside
count = SessionProcess.get_state(session_id, fn s -> s.count end)
```

## Common Patterns

### Pattern 1: Simple Counter

#### Before
```elixir
def handle_call(:increment, _from, state) do
  new_redux = Redux.dispatch(state.redux, :increment, fn s, :increment ->
    %{s | count: s.count + 1}
  end)
  {:reply, :ok, %{state | redux: new_redux}}
end

# Usage
Phoenix.SessionProcess.call(session_id, :increment)
```

#### After
```elixir
# Register reducer once
def user_init(_) do
  Phoenix.SessionProcess.register_reducer(get_session_id(), :counter, fn
    state, :increment -> %{state | count: state.count + 1}
    state, _ -> state
  end)
  %{count: 0}
end

# Usage
Phoenix.SessionProcess.dispatch(session_id, :increment)
```

### Pattern 2: Authentication

#### Before
```elixir
def handle_call({:login, user_id}, _from, state) do
  new_redux = Redux.dispatch(state.redux, {:set_user, user_id}, &auth_reducer/2)
  {:reply, :ok, %{state | redux: new_redux}}
end

defp auth_reducer(s, {:set_user, id}), do: %{s | user_id: id, authenticated: true}
defp auth_reducer(s, :logout), do: %{s | user_id: nil, authenticated: false}
defp auth_reducer(s, _), do: s
```

#### After
```elixir
def user_init(_) do
  Phoenix.SessionProcess.register_reducer(get_session_id(), :auth, fn
    s, {:set_user, id} -> %{s | user_id: id, authenticated: true}
    s, :logout -> %{s | user_id: nil, authenticated: false}
    s, _ -> s
  end)

  %{user_id: nil, authenticated: false}
end

# Usage
Phoenix.SessionProcess.dispatch(session_id, {:set_user, 123})
Phoenix.SessionProcess.dispatch(session_id, :logout)
```

### Pattern 3: Shopping Cart

#### Before
```elixir
def handle_call({:add_to_cart, item}, _from, state) do
  new_redux = Redux.dispatch(state.redux, {:add_item, item}, &cart_reducer/2)
  {:reply, :ok, %{state | redux: new_redux}}
end

defp cart_reducer(state, {:add_item, item}) do
  %{state | cart: [item | state.cart]}
end

defp cart_reducer(state, {:remove_item, item_id}) do
  %{state | cart: Enum.reject(state.cart, &(&1.id == item_id))}
end

defp cart_reducer(state, :clear_cart) do
  %{state | cart: []}
end

defp cart_reducer(state, _), do: state
```

#### After
```elixir
def user_init(_) do
  Phoenix.SessionProcess.register_reducer(get_session_id(), :cart, fn
    state, {:add_item, item} -> %{state | cart: [item | state.cart]}
    state, {:remove_item, id} -> %{state | cart: Enum.reject(state.cart, &(&1.id == id))}
    state, :clear_cart -> %{state | cart: []}
    state, _ -> state
  end)

  %{cart: [], total: 0}
end

# Usage
Phoenix.SessionProcess.dispatch(session_id, {:add_item, %{id: 1, name: "Widget"}})
Phoenix.SessionProcess.dispatch(session_id, {:remove_item, 1})
Phoenix.SessionProcess.dispatch(session_id, :clear_cart)
```

## API Reference

### New SessionProcess Functions

```elixir
# Dispatch (sync)
SessionProcess.dispatch(session_id, action)
# Returns: {:ok, new_state}

# Dispatch (async)
SessionProcess.dispatch(session_id, action, async: true)
# Returns: :ok

# Subscribe
SessionProcess.subscribe(session_id, selector_fn, event_name)
# Returns: {:ok, subscription_id}

# Unsubscribe
SessionProcess.unsubscribe(session_id, subscription_id)
# Returns: :ok

# Get state
SessionProcess.get_state(session_id)
# Returns: %{count: 0, user: nil, ...}

# Get state with selector
SessionProcess.get_state(session_id, fn state -> state.count end)
# Returns: 0

# Register reducer
SessionProcess.register_reducer(session_id, :name, reducer_fn)
# Returns: :ok

# Register middleware
SessionProcess.register_middleware(session_id, :name, middleware_fn)
# Returns: :ok
```

### Deprecated Redux Functions

| Old | New | Notes |
|-----|-----|-------|
| `Redux.init_state/1-2` | Built into `:process` macro | Use `init/1` |
| `Redux.dispatch/2-3` | `SessionProcess.dispatch/2-3` | Direct API |
| `Redux.subscribe/4` | `SessionProcess.subscribe/3` | Simplified |
| `Redux.unsubscribe/2` | `SessionProcess.unsubscribe/2` | Direct API |
| `Redux.get_state/1` | `SessionProcess.get_state/1-2` | Direct API |

## Troubleshooting

### Error: "Redux module not found"
**Solution**: Remove `alias Phoenix.SessionProcess.Redux` - you don't need it anymore!

### Error: "handle_call for :dispatch not defined"
**Solution**: Remove your custom `:dispatch` handler. The `:process` macro handles it now.

### Subscriptions not working
**Solution**: Use `SessionProcess.subscribe/3` instead of manual handlers.

### State structure issues
Change `state.redux.current_state.count` to `state.app_state.count`

## Testing

Update your tests:

```elixir
# Before
test "dispatch action" do
  {:ok, _pid} = SessionProcess.start("test_session")
  SessionProcess.call("test_session", {:dispatch, :increment})
  {:ok, state} = SessionProcess.call("test_session", :get_state)
  assert state.count == 1
end

# After
test "dispatch action" do
  {:ok, _pid} = SessionProcess.start("test_session")
  SessionProcess.dispatch("test_session", :increment)
  state = SessionProcess.get_state("test_session")
  assert state.count == 1
end
```

## Timeline

- **v0.6.0** (Current): New API available, Redux deprecated
- **v0.7.0** (+3 months): Stronger warnings
- **v0.8.0** (+6 months): Final grace period
- **v1.0.0** (+9 months): Redux module removed

## Benefits

After migration:

- ✅ 70% less boilerplate code
- ✅ Simpler mental model
- ✅ Better performance
- ✅ Easier testing
- ✅ More idiomatic Elixir

## Need Help?

- GitHub Issues: Report problems
- GitHub Discussions: Ask questions
- Examples: Check `/examples` directory

Thank you for using Phoenix.SessionProcess!
