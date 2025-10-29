# Phoenix.SessionProcess Redux Refactoring

## Executive Summary

This document describes the architectural refactoring to **make SessionProcess itself BE the Redux store**, eliminating the separate Redux module and struct. This simplification makes Redux state management a native feature of SessionProcess rather than an add-on.

## Current Architecture (Problems)

### Current Design
```elixir
# Redux struct stored in session process state
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

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

### Issues
1. **Redux is a nested struct** - Awkward `state.redux.current_state` access
2. **Manual Redux management** - Users must manually call `Redux.dispatch` and update state
3. **Confusing API** - Is Redux a separate concern or part of SessionProcess?
4. **Boilerplate** - Every dispatch requires pattern matching and state updating
5. **Not idiomatic** - Redux returns new structs instead of using GenServer naturally

## New Architecture (Solution)

### Core Principle: **SessionProcess IS the Redux Store**

```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  def init(_) do
    # Redux capabilities built-in
    {:ok, %{
      # Application state directly accessible
      app_state: %{count: 0, user: nil},

      # Redux infrastructure (managed by macro)
      _redux: %{
        reducers: %{},
        selectors: %{},
        subscriptions: [],
        middleware: [],
        history: []
      }
    }}
  end
end

# API is just SessionProcess
SessionProcess.dispatch(session_id, {:increment, 1})
SessionProcess.subscribe(session_id, fn state -> state.count end, :count_changed)
SessionProcess.get_state(session_id)  # Returns app_state directly
```

### Key Architectural Changes

#### 1. State Structure
**Old**: Redux struct nested inside GenServer state
```elixir
%{
  redux: %Redux{
    current_state: %{count: 0},
    subscriptions: [...],
    history: [...]
  },
  other_stuff: ...
}
```

**New**: Redux infrastructure flattened alongside app state
```elixir
%{
  # User's application state
  app_state: %{count: 0, user: nil},

  # Redux infrastructure (prefixed with _)
  _redux: %{
    reducers: %{counter: &CounterReducer.handle/2},
    selectors: %{count: fn s -> s.count end},
    subscriptions: [
      %{id: ref, pid: pid, selector: fn..., event_name: :count}
    ],
    middleware: [&logger/3],
    history: [{action, state, timestamp}]
  }
}
```

#### 2. API Changes

**Old Redux API**:
```elixir
# Get Redux from process
redux = Redux.init_state(%{count: 0})

# Dispatch returns new Redux
new_redux = Redux.dispatch(redux, action, reducer)

# Subscribe returns new Redux
{:ok, sub_id, new_redux} = Redux.subscribe(redux, selector, pid, event)

# Must manage Redux struct manually
```

**New SessionProcess API**:
```elixir
# Start session with initial state
SessionProcess.start(session_id, MyModule, initial_state: %{count: 0})

# Dispatch is a call/cast
SessionProcess.dispatch(session_id, {:increment, 1})
# or async
SessionProcess.dispatch(session_id, {:increment, 1}, async: true)

# Subscribe returns subscription ID
{:ok, sub_id} = SessionProcess.subscribe(session_id, selector, event_name)

# Get state
%{count: 1} = SessionProcess.get_state(session_id)

# With selector
1 = SessionProcess.get_state(session_id, fn s -> s.count end)

# Unsubscribe
:ok = SessionProcess.unsubscribe(session_id, sub_id)
```

#### 3. Macro Enhancement

The `:process` macro now injects Redux capabilities:

```elixir
defmacro __using__(:process) do
  quote do
    use GenServer

    # Existing start_link, get_session_id...

    # NEW: Default init with Redux structure
    @impl true
    def init(arg) do
      initial_app_state = user_init(arg)

      {:ok, %{
        app_state: initial_app_state,
        _redux: %{
          reducers: %{},
          selectors: %{},
          subscriptions: [],
          middleware: [],
          history: [],
          max_history_size: 100
        }
      }}
    end

    # User provides this (optional)
    def user_init(_arg), do: %{}
    defoverridable user_init: 1

    # NEW: Handle dispatch (sync)
    @impl true
    def handle_call({:dispatch, action}, _from, state) do
      {new_app_state, updated_redux} =
        __MODULE__.__redux_dispatch__(action, state.app_state, state._redux)

      new_state = %{state |
        app_state: new_app_state,
        _redux: updated_redux
      }

      {:reply, {:ok, new_app_state}, new_state}
    end

    # NEW: Handle dispatch (async)
    @impl true
    def handle_cast({:dispatch, action}, state) do
      {new_app_state, updated_redux} =
        __MODULE__.__redux_dispatch__(action, state.app_state, state._redux)

      new_state = %{state |
        app_state: new_app_state,
        _redux: updated_redux
      }

      {:noreply, new_state}
    end

    # NEW: Subscribe
    @impl true
    def handle_call({:subscribe, selector, pid, event_name}, _from, state) do
      {sub_id, updated_redux} =
        __MODULE__.__redux_subscribe__(selector, pid, event_name, state.app_state, state._redux)

      new_state = %{state | _redux: updated_redux}

      {:reply, {:ok, sub_id}, new_state}
    end

    # NEW: Unsubscribe
    @impl true
    def handle_call({:unsubscribe, sub_id}, _from, state) do
      updated_redux = __MODULE__.__redux_unsubscribe__(sub_id, state._redux)
      {:reply, :ok, %{state | _redux: updated_redux}}
    end

    # NEW: Register reducer
    @impl true
    def handle_call({:register_reducer, name, reducer_fn}, _from, state) do
      updated_redux = put_in(state._redux.reducers[name], reducer_fn)
      {:reply, :ok, %{state | _redux: updated_redux}}
    end

    # NEW: Get state
    @impl true
    def handle_call({:get_state, selector}, _from, state) do
      result = if selector do
        selector.(state.app_state)
      else
        state.app_state
      end

      {:reply, result, state}
    end

    # NEW: Handle process death
    @impl true
    def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
      updated_redux = __MODULE__.__redux_remove_by_monitor__(ref, state._redux)
      {:noreply, %{state | _redux: updated_redux}}
    end

    # Redux dispatch logic
    def __redux_dispatch__(action, app_state, redux) do
      # Apply all registered reducers
      new_app_state =
        Enum.reduce(redux.reducers, app_state, fn {_name, reducer}, acc ->
          reducer.(acc, action)
        end)

      # Add to history
      history_entry = %{
        action: action,
        timestamp: System.system_time(:millisecond)
      }

      new_history =
        [history_entry | redux.history]
        |> Enum.take(redux.max_history_size)

      # Notify subscriptions
      updated_subscriptions =
        __redux_notify_subscriptions__(
          redux.subscriptions,
          app_state,
          new_app_state
        )

      updated_redux = %{redux |
        subscriptions: updated_subscriptions,
        history: new_history
      }

      {new_app_state, updated_redux}
    end

    # Redux subscribe logic
    def __redux_subscribe__(selector, pid, event_name, app_state, redux) do
      sub_id = make_ref()
      monitor_ref = Process.monitor(pid)

      # Get initial value and send immediately
      initial_value = selector.(app_state)
      send(pid, {event_name, initial_value})

      subscription = %{
        id: sub_id,
        pid: pid,
        selector: selector,
        event_name: event_name,
        last_value: initial_value,
        monitor_ref: monitor_ref
      }

      updated_redux = %{redux |
        subscriptions: [subscription | redux.subscriptions]
      }

      {sub_id, updated_redux}
    end

    # Notification logic
    defp __redux_notify_subscriptions__(subscriptions, _old_state, new_state) do
      Enum.map(subscriptions, fn sub ->
        new_value = sub.selector.(new_state)

        if new_value != sub.last_value do
          send(sub.pid, {sub.event_name, new_value})
          %{sub | last_value: new_value}
        else
          sub
        end
      end)
    end

    # Other helpers...

    defoverridable [
      init: 1,
      handle_call: 3,
      handle_cast: 2,
      handle_info: 2
    ]
  end
end
```

#### 4. Public API Functions

Add to `Phoenix.SessionProcess`:

```elixir
@spec dispatch(binary(), action(), keyword()) :: {:ok, state()} | :ok | {:error, term()}
def dispatch(session_id, action, opts \\ []) do
  async = Keyword.get(opts, :async, false)

  if async do
    cast(session_id, {:dispatch, action})
  else
    call(session_id, {:dispatch, action})
  end
end

@spec subscribe(binary(), selector(), atom()) :: {:ok, reference()} | {:error, term()}
def subscribe(session_id, selector, event_name \\ :state_changed) do
  call(session_id, {:subscribe, selector, self(), event_name})
end

@spec unsubscribe(binary(), reference()) :: :ok | {:error, term()}
def unsubscribe(session_id, sub_id) do
  call(session_id, {:unsubscribe, sub_id})
end

@spec register_reducer(binary(), atom(), function()) :: :ok | {:error, term()}
def register_reducer(session_id, name, reducer_fn) do
  call(session_id, {:register_reducer, name, reducer_fn})
end

@spec get_state(binary(), selector() | nil) :: any()
def get_state(session_id, selector \\ nil) do
  call(session_id, {:get_state, selector})
end
```

## Migration Path

### Phase 1: Add New API (Non-Breaking)
1. Add new Redux functions to `Phoenix.SessionProcess`
2. Update `:process` macro with Redux capabilities
3. Keep `Redux` module as-is for backward compatibility
4. All new code works, old code continues working

### Phase 2: Deprecation Warnings
1. Add deprecation warnings to `Redux` module
2. Create migration guide
3. Update documentation
4. Give users 1-2 major versions to migrate

### Phase 3: Remove Redux Module
1. Delete `lib/phoenix/session_process/redux.ex`
2. Keep utility modules (`Redux.Selector`, `Redux.Subscription`)
3. Move them to `SessionProcess.Selector`, `SessionProcess.Subscription`

### Backward Compatibility Strategy

Create a shim in `Redux` module:

```elixir
defmodule Phoenix.SessionProcess.Redux do
  @moduledoc false
  @deprecated """
  Phoenix.SessionProcess.Redux is deprecated.

  SessionProcess IS now the Redux store. Use SessionProcess directly:

  Old:
    redux = Redux.init_state(%{count: 0})
    new_redux = Redux.dispatch(redux, action, reducer)

  New:
    SessionProcess.start(session_id, MyModule, initial_state: %{count: 0})
    SessionProcess.dispatch(session_id, action)

  See migration guide: [link]
  """

  # Provide shim functions that work with SessionProcess
  def init_state(initial_state, _opts \\ []) do
    IO.warn("Redux.init_state/2 is deprecated. Initialize state in your module's init/1 callback.")
    initial_state
  end

  def dispatch(state_or_session_id, action, reducer \\ nil) do
    IO.warn("Redux.dispatch/3 is deprecated. Use SessionProcess.dispatch/2 instead.")

    # If it's a binary (session_id), dispatch via SessionProcess
    if is_binary(state_or_session_id) do
      Phoenix.SessionProcess.dispatch(state_or_session_id, action)
    else
      # Old Redux struct - try to handle it
      # This is a last-resort compatibility layer
      if reducer do
        new_state = reducer.(state_or_session_id, action)
        new_state
      else
        state_or_session_id
      end
    end
  end

  # ... other shim functions
end
```

## File Structure Changes

### Files to Modify
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/lib/phoenix/session_process.ex`
  - Add: `dispatch/3`, `subscribe/3`, `unsubscribe/2`, `register_reducer/3`, `get_state/2`
  - Update: `:process` macro with Redux capabilities

### Files to Deprecate
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/lib/phoenix/session_process/redux.ex`
  - Add deprecation warnings
  - Add shim functions

### Files to Rename (Future)
- `lib/phoenix/session_process/redux/selector.ex` → `lib/phoenix/session_process/selector.ex`
- `lib/phoenix/session_process/redux/subscription.ex` → `lib/phoenix/session_process/subscription.ex`
- `lib/phoenix/session_process/redux/live_view.ex` → Update to use new API

### Files to Update
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/lib/phoenix/session_process/live_view.ex`
  - Update to use `SessionProcess.dispatch/subscribe` directly

### Tests to Update
- `test/phoenix/session_process/redux_test.exs` - Update to new API
- `test/phoenix/session_process/redux_integration_test.exs` - Update to new API
- Create `test/phoenix/session_process/dispatch_test.exs` - New tests

### Documentation to Update
- `CLAUDE.md` - Update architecture section
- `README.md` - Update examples
- Create `MIGRATION.md` - Migration guide from Redux to SessionProcess

## Benefits of New Architecture

### 1. Simpler Mental Model
- "SessionProcess IS the Redux store" - one concept, not two
- No nested structs - flat state access
- Natural GenServer patterns - call/cast for actions

### 2. Less Boilerplate
```elixir
# Old
def handle_call({:dispatch, action}, _from, state) do
  new_redux = Redux.dispatch(state.redux, action, &reducer/2)
  {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
end

# New
SessionProcess.dispatch(session_id, action)  # That's it!
```

### 3. Better Ergonomics
- Dispatch is just a call/cast - async naturally supported
- Subscriptions managed by process - automatic cleanup
- State access direct - no unwrapping

### 4. More Idiomatic Elixir
- Leverages GenServer natively
- Process-based, not struct-based
- Familiar patterns for Elixir developers

### 5. Clearer Boundaries
- Redux utilities (Selector, Subscription) are helpers, not core
- SessionProcess owns state and lifecycle
- No confusion about "where does Redux end and SessionProcess begin?"

## Risks and Mitigations

### Risk 1: Breaking Changes
**Mitigation**:
- Phase 1 is non-breaking - new API alongside old
- Deprecation warnings give users time
- Comprehensive migration guide
- Shim functions for common cases

### Risk 2: Complex Migration
**Mitigation**:
- Automated migration script: `mix session_process.migrate_redux`
- Before/after examples in docs
- Step-by-step guide
- Support in GitHub discussions

### Risk 3: Existing Codebases
**Mitigation**:
- Keep old API working for 2 major versions
- Clear deprecation timeline
- Version-specific documentation
- Community feedback period

### Risk 4: Learning Curve
**Mitigation**:
- New API is actually simpler
- Better documentation
- More examples
- Migration guides with real-world scenarios

## Implementation Checklist

### Phase 1: Core Implementation (Non-Breaking)
- [ ] Add Redux state structure to `:process` macro
- [ ] Implement dispatch handling in macro
- [ ] Implement subscription handling in macro
- [ ] Add public API functions to `Phoenix.SessionProcess`
- [ ] Add tests for new API
- [ ] Ensure old Redux API still works

### Phase 2: Documentation
- [ ] Create `MIGRATION.md` guide
- [ ] Update `CLAUDE.md` architecture docs
- [ ] Update `README.md` examples
- [ ] Add inline documentation
- [ ] Create migration script

### Phase 3: LiveView Integration
- [ ] Update `Redux.LiveView` to use new API
- [ ] Create `SessionProcess.LiveView` helper
- [ ] Update examples
- [ ] Add tests

### Phase 4: Deprecation
- [ ] Add deprecation warnings to Redux module
- [ ] Create shim functions
- [ ] Update tests to use new API
- [ ] Announce deprecation

### Phase 5: Cleanup (Future Major Version)
- [ ] Remove Redux module
- [ ] Rename utility modules
- [ ] Remove shim code
- [ ] Final documentation update

## Timeline

- **v0.6.0**: Phase 1 + 2 (new API, docs) - NEXT RELEASE
- **v0.7.0**: Phase 3 (LiveView, deprecations)
- **v0.8.0**: Grace period, community feedback
- **v1.0.0**: Phase 4 + 5 (remove Redux module)

## API Comparison

### Old Redux API
```elixir
# Initialize
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  def init(_) do
    redux = Redux.init_state(%{count: 0})
    {:ok, %{redux: redux}}
  end

  # Dispatch
  def handle_call({:dispatch, action}, _from, state) do
    new_redux = Redux.dispatch(state.redux, action, &reducer/2)
    {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
  end

  # Subscribe
  def handle_call({:subscribe, selector, pid}, _from, state) do
    {:ok, sub_id, new_redux} = Redux.subscribe(state.redux, selector, pid, :event)
    {:reply, {:ok, sub_id}, %{state | redux: new_redux}}
  end

  # Get state
  def handle_call(:get_state, _from, state) do
    {:reply, Redux.get_state(state.redux), state}
  end

  defp reducer(state, {:increment, val}), do: %{state | count: state.count + val}
  defp reducer(state, _), do: state
end

# Usage
SessionProcess.call(session_id, {:dispatch, {:increment, 1}})
SessionProcess.call(session_id, {:subscribe, fn s -> s.count end, self()})
SessionProcess.call(session_id, :get_state)
```

### New SessionProcess API
```elixir
# Initialize
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process

  def init(_) do
    # Redux capabilities built-in!
    {:ok, %{app_state: %{count: 0}}}
  end

  # Register reducer on init or later
  def user_init(_) do
    session_id = get_session_id()
    SessionProcess.register_reducer(session_id, :counter, &reducer/2)
    %{count: 0}
  end

  defp reducer(state, {:increment, val}), do: %{state | count: state.count + val}
  defp reducer(state, _), do: state
end

# Usage - much simpler!
SessionProcess.dispatch(session_id, {:increment, 1})
SessionProcess.subscribe(session_id, fn s -> s.count end, :count_changed)
SessionProcess.get_state(session_id)

# Or async dispatch
SessionProcess.dispatch(session_id, {:increment, 1}, async: true)

# With selector
count = SessionProcess.get_state(session_id, fn s -> s.count end)
```

## Conclusion

This refactoring **simplifies the architecture** by making SessionProcess BE the Redux store, eliminating the nested Redux struct and manual state management. It provides:

1. **Simpler API** - Direct dispatch/subscribe on SessionProcess
2. **Less boilerplate** - No manual Redux struct management
3. **Better ergonomics** - Natural GenServer patterns
4. **Clearer architecture** - One store concept, not two
5. **Backward compatible** - Old code continues working with deprecation warnings

The migration path is gradual and well-supported, allowing users to adopt the new API at their own pace while maintaining backward compatibility for existing applications.
