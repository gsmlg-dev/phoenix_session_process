# Migration Guide: v0.5.x → v0.6.0

Quick guide to migrating from old Redux API to the new Redux Store API.

## What Changed?

**v0.6.0 makes SessionProcess itself a Redux store**. No more managing separate Redux structs!

## Quick Migration Steps

### Step 1: Update Session Process

**Before (v0.5.x):**
```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process
  alias Phoenix.SessionProcess.Redux

  @impl true
  def init(_args) do
    redux = Redux.init_state(
      %{count: 0, user: nil},
      pubsub: MyApp.PubSub,
      pubsub_topic: "session:#{get_session_id()}:redux"
    )
    {:ok, %{redux: redux}}
  end

  @impl true
  def handle_cast(:increment, state) do
    new_redux = Redux.dispatch(state.redux, :increment, &reducer/2)
    {:noreply, %{state | redux: new_redux}}
  end

  @impl true
  def handle_call(:get_redux_state, _from, state) do
    {:reply, {:ok, state.redux}, state}
  end

  defp reducer(state, :increment), do: %{state | count: state.count + 1}
end
```

**After (v0.6.0):**
```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  # Just return initial state!
  def user_init(_args) do
    %{count: 0, user: nil}
  end
end

# Register reducer elsewhere (controller or LiveView):
reducer = fn state, action ->
  case action do
    :increment -> %{state | count: state.count + 1}
    _ -> state
  end
end

Phoenix.SessionProcess.register_reducer(session_id, :counter, reducer)

# Dispatch actions:
{:ok, new_state} = Phoenix.SessionProcess.dispatch(session_id, :increment)
```

### Step 2: Update LiveView

**Before (v0.5.x):**
```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess.LiveView, as: SessionLV

  def mount(_params, %{"session_id" => session_id}, socket) do
    case SessionLV.mount_session(socket, session_id, MyApp.PubSub) do
      {:ok, socket, state} ->
        {:ok, assign(socket, state: state)}
    end
  end

  def handle_info({:redux_state_change, %{state: new_state}}, socket) do
    {:noreply, assign(socket, state: new_state)}
  end

  def handle_event("increment", _params, socket) do
    SessionLV.dispatch_async(socket.assigns.session_id, :increment)
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    SessionLV.unmount_session(socket)
    :ok
  end
end
```

**After (v0.6.0):**
```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess.LiveView, as: SessionLV

  def mount(_params, %{"session_id" => session_id}, socket) do
    case SessionLV.mount_store(socket, session_id) do
      {:ok, socket, state} ->
        {:ok, assign(socket, state: state, session_id: session_id)}
    end
  end

  def handle_info({:state_changed, new_state}, socket) do
    {:noreply, assign(socket, state: new_state)}
  end

  def handle_event("increment", _params, socket) do
    SessionLV.dispatch_store(socket.assigns.session_id, :increment, async: true)
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    # Optional - cleanup is automatic!
    SessionLV.unmount_store(socket)
    :ok
  end
end
```

## API Changes Summary

| Old API | New API |
|---------|---------|
| `Redux.init_state(state, opts)` | `def user_init(_), do: state` |
| `Redux.dispatch(redux, action, reducer)` | `SessionProcess.dispatch(session_id, action)` |
| `Redux.subscribe(redux, selector, callback)` | `SessionProcess.subscribe(session_id, selector, event, pid)` |
| `Redux.get_state(redux)` | `SessionProcess.get_state(session_id)` |
| `SessionLV.mount_session(socket, id, pubsub)` | `SessionLV.mount_store(socket, id)` |
| `SessionLV.unmount_session(socket)` | `SessionLV.unmount_store(socket)` |
| `SessionLV.dispatch_async(id, msg)` | `SessionLV.dispatch_store(id, action, async: true)` |
| `{:redux_state_change, %{state: s}}` | `{:state_changed, s}` |

## Key Benefits

- **70% less boilerplate** - No Redux struct to manage
- **Simpler code** - Direct SessionProcess integration
- **Better performance** - Selector-based updates
- **Automatic cleanup** - Process monitoring handles subscriptions
- **No PubSub config** - Direct subscriptions to SessionProcess

## Deprecation Warnings

Old code still works but will show deprecation warnings:

```
[warning] [Phoenix.SessionProcess.Redux] DEPRECATION WARNING
Function: Redux.init_state/2
Status: This module is deprecated as of v0.6.0 and will be removed in v1.0.0

Migration: Define user_init/1 callback in your SessionProcess module

See REDUX_TO_SESSIONPROCESS_MIGRATION.md for detailed examples.
```

## Migration Timeline

- **v0.6.0**: Old API deprecated, new API available
- **v0.7.x-v0.9.x**: Both APIs supported (grace period)
- **v1.0.0**: Old API removed

## Need Help?

- **Detailed guide**: See `REDUX_TO_SESSIONPROCESS_MIGRATION.md`
- **Examples**: See `examples/liveview_redux_store_example.ex`
- **Phase summaries**: See `PHASE_1_IMPLEMENTATION_SUMMARY.md`, `PHASE_2_DEPRECATION_SUMMARY.md`, `PHASE_3_LIVEVIEW_SUMMARY.md`

## Selector-Based Subscriptions (NEW!)

One of the most powerful new features:

```elixir
# Subscribe only to user changes (efficient!)
{:ok, sub_id} = Phoenix.SessionProcess.subscribe(
  session_id,
  fn state -> state.user end,  # Selector function
  :user_changed,               # Event name
  self()                       # Subscriber PID
)

# Only receive messages when user actually changes
def handle_info({:user_changed, user}, socket) do
  {:noreply, assign(socket, user: user)}
end
```

This prevents unnecessary updates and improves performance.

## Common Migration Issues

### Issue 1: "undefined function user_init/1"

**Problem**: Forgot to add `user_init/1` callback.

**Solution**: Add the callback to your session process:
```elixir
def user_init(_args) do
  %{your: "initial", state: "here"}
end
```

### Issue 2: "No reducer registered"

**Problem**: Dispatching actions without registered reducer.

**Solution**: Register reducer before dispatching:
```elixir
Phoenix.SessionProcess.register_reducer(session_id, :main, fn state, action ->
  # your reducer logic
end)
```

### Issue 3: "Pattern match failed" in handle_info

**Problem**: Still using old message format `{:redux_state_change, %{state: s}}`.

**Solution**: Update to new format `{:state_changed, s}`:
```elixir
# Old:
def handle_info({:redux_state_change, %{state: new_state}}, socket)

# New:
def handle_info({:state_changed, new_state}, socket)
```

## Still Using Old API?

That's fine! The old API will continue to work through v0.9.x. You have time to migrate.

When you're ready:
1. Update one session process at a time
2. Update its corresponding LiveView
3. Test thoroughly
4. Repeat for other processes

## Questions?

Open an issue at: https://github.com/gsmlg-dev/phoenix_session_process/issues
