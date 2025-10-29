# Phoenix.SessionProcess v0.6.0 Release Notes

Released: October 29, 2025

## Overview

Version 0.6.0 introduces the **Redux Store API**, a major architectural improvement that makes SessionProcess itself the Redux store. This eliminates the need for separate Redux struct management while providing 70% less boilerplate and better performance.

**Key Highlight**: SessionProcess IS the Redux store - no more manual struct management!

## What's New

### 1. Redux Store API

The new Redux Store API integrates Redux functionality directly into SessionProcess:

```elixir
# Define initial state - that's it!
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  def user_init(_args) do
    %{count: 0, user: nil, cart_items: []}
  end
end

# Register reducers
Phoenix.SessionProcess.register_reducer(session_id, :counter, fn state, action ->
  case action do
    :increment -> %{state | count: state.count + 1}
    _ -> state
  end
end)

# Dispatch actions
{:ok, new_state} = Phoenix.SessionProcess.dispatch(session_id, :increment)

# Subscribe with selectors
{:ok, sub_id} = Phoenix.SessionProcess.subscribe(
  session_id,
  fn state -> state.count end,  # Selector - only notifies when count changes
  :count_changed,
  self()
)
```

**New Functions**:
- `dispatch/3` - Dispatch actions (sync or async)
- `subscribe/4` - Subscribe with optional selectors
- `unsubscribe/2` - Remove subscriptions
- `register_reducer/3` - Register named reducers
- `register_selector/3` - Register named selectors
- `get_state/2` - Get state with optional selector
- `select/2` - Apply registered selector
- `user_init/1` - Callback for initial Redux state

### 2. Enhanced LiveView Integration

New LiveView helpers designed for the Redux Store API:

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView
  alias Phoenix.SessionProcess.LiveView, as: SessionLV

  def mount(_params, %{"session_id" => session_id}, socket) do
    # Mount with Redux Store - no PubSub needed!
    case SessionLV.mount_store(socket, session_id) do
      {:ok, socket, state} ->
        {:ok, assign(socket, state: state, session_id: session_id)}
    end
  end

  # Simpler message format
  def handle_info({:state_changed, new_state}, socket) do
    {:noreply, assign(socket, state: new_state)}
  end

  def handle_event("increment", _params, socket) do
    # Async dispatch
    :ok = SessionLV.dispatch_store(socket.assigns.session_id, :increment, async: true)
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    # Optional - cleanup is automatic via process monitoring!
    SessionLV.unmount_store(socket)
    :ok
  end
end
```

**New Functions**:
- `mount_store/4` - Mount with direct SessionProcess subscriptions
- `unmount_store/1` - Clean up subscriptions (optional, automatic cleanup)
- `dispatch_store/3` - Dispatch with sync/async options

### 3. Selector-Based Subscriptions

Subscribe to specific parts of state for efficient updates:

```elixir
# Subscribe only to user changes
{:ok, _sub_id} = Phoenix.SessionProcess.subscribe(
  session_id,
  fn state -> state.user end,
  :user_changed,
  self()
)

# Subscribe only to cart total
{:ok, _sub_id} = Phoenix.SessionProcess.subscribe(
  session_id,
  fn state -> state.cart_total end,
  :cart_total_changed,
  self()
)

# Handle specific updates
def handle_info({:user_changed, user}, socket) do
  {:noreply, assign(socket, user: user)}
end

def handle_info({:cart_total_changed, total}, socket) do
  {:noreply, assign(socket, cart_total: total)}
end
```

**Benefits**:
- Only receive updates when selected values actually change
- Reduces unnecessary message passing
- Improves performance for complex state trees
- Memoized selector support

### 4. Automatic Subscription Cleanup

Process monitoring ensures subscriptions are automatically cleaned up when LiveView processes terminate. No more manual cleanup needed!

```elixir
def terminate(_reason, socket) do
  # Cleanup happens automatically via process monitoring!
  # But you can still call unmount_store/1 explicitly if desired
  :ok
end
```

## Key Benefits

### 70% Less Boilerplate

**Before (v0.5.x)**:
```elixir
defmodule OldSessionProcess do
  use Phoenix.SessionProcess, :process
  alias Phoenix.SessionProcess.Redux

  def init(_args) do
    redux = Redux.init_state(
      %{count: 0},
      pubsub: MyApp.PubSub,
      pubsub_topic: "session:#{get_session_id()}:redux"
    )
    {:ok, %{redux: redux}}
  end

  def handle_call(:get_redux_state, _from, state) do
    {:reply, {:ok, state.redux}, state}
  end

  def handle_cast(:increment, state) do
    new_redux = Redux.dispatch(state.redux, :increment, &reducer/2)
    {:noreply, %{state | redux: new_redux}}
  end

  defp reducer(state, :increment), do: %{state | count: state.count + 1}
end
```

**After (v0.6.0)**:
```elixir
defmodule NewSessionProcess do
  use Phoenix.SessionProcess, :process

  def user_init(_args) do
    %{count: 0}
  end
end

# Register reducer externally
Phoenix.SessionProcess.register_reducer(session_id, :counter, fn state, :increment ->
  %{state | count: state.count + 1}
end)
```

### Simpler Architecture

- **No Redux Struct**: SessionProcess handles Redux infrastructure internally
- **No PubSub Config**: Direct subscriptions to SessionProcess
- **No Manual Cleanup**: Process monitoring handles subscription lifecycle
- **Fewer Concepts**: Less nesting, clearer code intent

### Better Performance

- **Selector-Based Updates**: Only receive notifications when selected values change
- **Automatic Equality Checking**: Prevents duplicate notifications
- **Memoized Selectors**: Efficient derived state calculations
- **Reduced Message Passing**: Fine-grained state subscriptions

## Migration Guide

### Quick 2-Step Migration

#### Step 1: Update Session Process

Replace `Redux.init_state` with `user_init/1`:

```elixir
# Before
def init(_args) do
  redux = Redux.init_state(%{count: 0}, pubsub: MyApp.PubSub, ...)
  {:ok, %{redux: redux}}
end

# After
def user_init(_args) do
  %{count: 0}
end
```

#### Step 2: Update LiveView

Replace `mount_session` with `mount_store`:

```elixir
# Before
SessionLV.mount_session(socket, session_id, MyApp.PubSub)

# After
SessionLV.mount_store(socket, session_id)
```

Update message handlers:

```elixir
# Before
def handle_info({:redux_state_change, %{state: new_state}}, socket)

# After
def handle_info({:state_changed, new_state}, socket)
```

### Detailed Migration Resources

- **Quick Guide**: See `MIGRATION_GUIDE.md` for 2-step process
- **Detailed Guide**: See `REDUX_TO_SESSIONPROCESS_MIGRATION.md` for comprehensive examples
- **Working Example**: See `examples/liveview_redux_store_example.ex` (400+ lines)
- **Common Issues**: See `MIGRATION_GUIDE.md` for troubleshooting

## Backward Compatibility

### No Breaking Changes

All existing code continues to work with deprecation warnings:

- Old `Redux` module API still functions correctly
- Old `LiveView` helpers (`mount_session`, etc.) still work
- Deprecation warnings guide you to new API
- 100% backward compatible

### Deprecation Timeline

- **v0.6.0**: Old API deprecated, new API available
- **v0.7.x - v0.9.x**: Both APIs supported (grace period)
- **v1.0.0**: Old API removed

### Deprecation Warnings

When using deprecated functions, you'll see helpful warnings:

```
[warning] [Phoenix.SessionProcess.Redux] DEPRECATION WARNING
Function: Redux.init_state/2
Status: This module is deprecated as of v0.6.0 and will be removed in v1.0.0

Migration: Define user_init/1 callback in your SessionProcess module

See REDUX_TO_SESSIONPROCESS_MIGRATION.md for detailed examples.
```

## Documentation Updates

### New Documentation

- **MIGRATION_GUIDE.md**: Quick 2-step migration guide (248 lines)
- **RELEASE_NOTES_v0.6.0.md**: This file - comprehensive release notes
- **examples/liveview_redux_store_example.ex**: Complete working example (400+ lines)

### Updated Documentation

- **CLAUDE.md**: Updated with Redux Store API as recommended approach
- **README.md**: Updated quick start and API reference
- **CHANGELOG.md**: Complete v0.6.0 changelog entry

### Documentation Hierarchy

1. **Quick Start**: README.md
2. **Migration**: MIGRATION_GUIDE.md (2-step process)
3. **Architecture**: CLAUDE.md (comprehensive overview)
4. **Detailed Migration**: REDUX_TO_SESSIONPROCESS_MIGRATION.md
5. **Examples**: examples/liveview_redux_store_example.ex
6. **Implementation**: PHASE_1-4_IMPLEMENTATION_SUMMARY.md

## API Changes

### New Public API

**Phoenix.SessionProcess**:
```elixir
dispatch(session_id, action, opts \\ [])
subscribe(session_id, selector, event_name, subscriber_pid)
unsubscribe(session_id, subscription_id)
register_reducer(session_id, reducer_name, reducer_fn)
register_selector(session_id, selector_name, selector_fn)
get_state(session_id, selector \\ &Function.identity/1)
select(session_id, selector_name)
```

**Phoenix.SessionProcess.LiveView**:
```elixir
mount_store(socket, session_id, selector \\ &Function.identity/1, event_name \\ :state_changed)
unmount_store(socket)
dispatch_store(session_id, action, opts \\ [])
```

### Deprecated API

**Phoenix.SessionProcess.Redux** (all functions deprecated):
- `init_state/2` → Use `user_init/1` callback
- `dispatch/3` → Use `SessionProcess.dispatch/3`
- `subscribe/3` → Use `SessionProcess.subscribe/4`
- `get_state/1` → Use `SessionProcess.get_state/2`

**Phoenix.SessionProcess.LiveView** (old helpers deprecated):
- `mount_session/4` → Use `mount_store/4`
- `unmount_session/1` → Use `unmount_store/1`
- `dispatch_async/2` → Use `dispatch_store/3` with `async: true`

## Testing

### Test Results

All 195 tests pass with 0 failures:

```bash
Finished in 3.6 seconds (2.5s async, 1.1s sync)
195 tests, 0 failures
```

### Test Coverage

- 20 new tests added for Redux Store API
- All existing tests passing (backward compatibility verified)
- No regressions introduced

## Performance

### Expected Performance

Same high performance as previous versions:
- **Session Creation**: 10,000+ sessions/second
- **Memory Usage**: ~10KB per session
- **Registry Lookups**: 100,000+ lookups/second

### Performance Improvements

- Selector-based subscriptions reduce unnecessary updates
- Direct subscriptions eliminate PubSub overhead
- Automatic cleanup reduces memory leaks

## Upgrading

### Update Dependency

Update your `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_session_process, "~> 0.6.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

### Update Code (Optional)

Your existing code continues to work! You can migrate at your own pace:

1. Update one session process at a time
2. Update corresponding LiveViews
3. Test thoroughly
4. Repeat for other processes

### Migration Assistance

If you encounter issues during migration:

1. Check `MIGRATION_GUIDE.md` for common issues
2. Review `examples/liveview_redux_store_example.ex` for working examples
3. Open an issue at: https://github.com/gsmlg-dev/phoenix_session_process/issues

## Contributors

This release represents 4 phases of careful refactoring:

- **Phase 1**: Core SessionProcess enhancements (8 new functions)
- **Phase 2**: Deprecation layer and warnings
- **Phase 3**: LiveView integration updates (3 new helpers)
- **Phase 4**: Documentation and polish

All work completed with 100% backward compatibility and comprehensive testing.

## Thank You

Thank you for using Phoenix.SessionProcess! We hope the new Redux Store API makes your session management simpler and more efficient.

## Questions?

- **Documentation**: See README.md and CLAUDE.md
- **Migration Help**: See MIGRATION_GUIDE.md
- **Issues**: https://github.com/gsmlg-dev/phoenix_session_process/issues
- **Discussions**: https://github.com/gsmlg-dev/phoenix_session_process/discussions

---

**Happy Coding!** 🎉
