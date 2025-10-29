# Implementation Plan: Redux Native Integration

## Overview

This document outlines the implementation plan for making SessionProcess natively support Redux patterns without the separate Redux module.

## Files to Modify/Create

### 1. Core Module Updates

#### `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/lib/phoenix/session_process.ex`
**Changes**:
- Add `dispatch/2` and `dispatch/3` functions
- Add `subscribe/3` function
- Add `unsubscribe/2` function
- Add `register_reducer/3` function
- Add `register_middleware/3` function
- Update `get_state/1` to accept optional selector
- Add `get_state/2` with selector support
- Update `:process` macro to inject Redux infrastructure

**Estimated LOC**: +400 lines

#### Key New Functions:
```elixir
@spec dispatch(binary(), action(), keyword()) :: {:ok, state()} | :ok | {:error, term()}
def dispatch(session_id, action, opts \\ [])

@spec subscribe(binary(), selector(), atom()) :: {:ok, reference()} | {:error, term()}
def subscribe(session_id, selector, event_name \\ :state_changed)

@spec unsubscribe(binary(), reference()) :: :ok | {:error, term()}
def unsubscribe(session_id, sub_id)

@spec register_reducer(binary(), atom(), reducer()) :: :ok | {:error, term()}
def register_reducer(session_id, name, reducer_fn)

@spec register_middleware(binary(), atom(), middleware()) :: :ok | {:error, term()}
def register_middleware(session_id, name, middleware_fn)

@spec get_state(binary(), selector() | nil) :: any()
def get_state(session_id, selector \\ nil)
```

### 2. Deprecation Layer

#### `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/lib/phoenix/session_process/redux.ex`
**Changes**:
- Add `@deprecated` module attribute
- Add deprecation warnings to all functions
- Add shim functions that delegate to SessionProcess
- Keep type definitions for backward compatibility

**Estimated LOC**: Modify ~700 lines, add ~100 deprecation lines

#### Shim Examples:
```elixir
@deprecated """
Use Phoenix.SessionProcess directly instead.
See REDUX_TO_SESSIONPROCESS_MIGRATION.md for migration guide.
"""

@spec init_state(state(), keyword()) :: state()
def init_state(initial_state, _opts \\ []) do
  IO.warn("""
  Redux.init_state/2 is deprecated.
  Initialize state in your module's init/1 callback instead.
  """, Macro.Env.stacktrace(__CALLER__))

  initial_state
end

@spec dispatch(state_or_session_id, action(), reducer() | nil) :: state()
def dispatch(state_or_session_id, action, reducer \\ nil) do
  IO.warn("""
  Redux.dispatch/3 is deprecated.
  Use Phoenix.SessionProcess.dispatch/2 instead.
  """, Macro.Env.stacktrace(__CALLER__))

  # Backward compatibility shim
  if is_binary(state_or_session_id) do
    Phoenix.SessionProcess.dispatch(state_or_session_id, action)
  else
    # Fallback for old Redux struct usage
    if reducer do
      reducer.(state_or_session_id, action)
    else
      state_or_session_id
    end
  end
end
```

### 3. Helper Modules (Keep, but rename in future)

#### `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/lib/phoenix/session_process/redux/selector.ex`
**Changes**:
- Add note about future rename to `SessionProcess.Selector`
- No immediate code changes
- Works with new API

#### `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/lib/phoenix/session_process/redux/subscription.ex`
**Changes**:
- Add note about integration with SessionProcess
- Functions now work with new SessionProcess API
- Minimal changes needed

### 4. LiveView Integration

#### `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/lib/phoenix/session_process/redux/live_view.ex`
**Changes**:
- Update `mount_session/4` to use `SessionProcess.subscribe`
- Update `dispatch_to_session/2` to use `SessionProcess.dispatch`
- Add deprecation warnings for old callback-based API
- Keep module for backward compatibility

**Estimated LOC**: ~50 lines modified

#### New Implementation:
```elixir
def mount_session(socket, session_id, selector_fn, event_name \\ :redux_state_change) do
  # New: Direct SessionProcess API
  case Phoenix.SessionProcess.subscribe(session_id, selector_fn, event_name) do
    {:ok, sub_id} ->
      Phoenix.Component.assign(socket, :__redux_subscription_id__, sub_id)
    {:error, _reason} ->
      socket
  end
end

def dispatch_to_session(session_id, action) do
  Phoenix.SessionProcess.dispatch(session_id, action)
end
```

### 5. Tests

#### Update existing tests:
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/test/phoenix/session_process/redux_test.exs`
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/test/phoenix/session_process/redux_integration_test.exs`

#### Create new tests:
- `test/phoenix/session_process/dispatch_test.exs` - Test new dispatch API
- `test/phoenix/session_process/subscribe_test.exs` - Test new subscribe API
- `test/phoenix/session_process/reducer_test.exs` - Test reducer registration

**Estimated LOC**: ~500 lines of new tests

### 6. Documentation

#### Update:
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/CLAUDE.md` - Architecture section
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/README.md` - Examples and API

#### Create:
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/ARCHITECTURE_REFACTORING.md` ✅ Done
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/REDUX_TO_SESSIONPROCESS_MIGRATION.md` ✅ Done
- `/Users/gao/Workspace/gsmlg-dev/phoenix_session_process/IMPLEMENTATION_PLAN.md` ✅ This file

## Implementation Phases

### Phase 1: Core SessionProcess Updates (Week 1)
**Goal**: Add Redux capabilities to SessionProcess without breaking changes

1. **Update `:process` macro** (3-4 hours)
   - Add default `init/1` that creates Redux infrastructure
   - Add `user_init/1` callback for user customization
   - Add handlers for `handle_call` and `handle_cast`
   - Add `handle_info` for :DOWN monitoring

2. **Add public API functions** (2-3 hours)
   - Implement `dispatch/2-3`
   - Implement `subscribe/3`
   - Implement `unsubscribe/2`
   - Implement `register_reducer/3`
   - Implement `register_middleware/3`
   - Update `get_state/1-2`

3. **Add private helper functions** (1-2 hours)
   - `__redux_dispatch__/3`
   - `__redux_subscribe__/5`
   - `__redux_unsubscribe__/2`
   - `__redux_notify_subscriptions__/3`
   - `__redux_remove_by_monitor__/2`

4. **Testing** (3-4 hours)
   - Write comprehensive tests
   - Test sync/async dispatch
   - Test subscriptions
   - Test reducer registration
   - Test process monitoring

**Deliverables**:
- ✅ Updated `lib/phoenix/session_process.ex`
- ✅ New test files
- ✅ All tests passing

### Phase 2: Deprecation Layer (Week 1-2)
**Goal**: Deprecate Redux module gracefully

1. **Add deprecation warnings** (1-2 hours)
   - Add `@deprecated` to Redux module
   - Add warnings to all public functions
   - Create helpful error messages

2. **Create shim functions** (2-3 hours)
   - Implement backward-compatible wrappers
   - Handle both old and new usage patterns
   - Add migration suggestions in warnings

3. **Testing** (2 hours)
   - Ensure old code still works
   - Verify deprecation warnings appear
   - Test shim functions

**Deliverables**:
- ✅ Updated `lib/phoenix/session_process/redux.ex`
- ✅ Backward compatibility tests
- ✅ Deprecation warnings working

### Phase 3: LiveView Integration (Week 2)
**Goal**: Update LiveView helpers to use new API

1. **Update Redux.LiveView module** (2-3 hours)
   - Refactor to use SessionProcess API
   - Keep backward compatibility
   - Add deprecation warnings for old patterns

2. **Testing** (1-2 hours)
   - Test LiveView subscription lifecycle
   - Test cleanup on terminate
   - Test with both APIs

**Deliverables**:
- ✅ Updated `lib/phoenix/session_process/redux/live_view.ex`
- ✅ LiveView integration tests

### Phase 4: Documentation (Week 2-3)
**Goal**: Comprehensive migration docs

1. **Update existing docs** (3-4 hours)
   - Update README with new examples
   - Update CLAUDE.md architecture
   - Update module documentation

2. **Migration guide** (2-3 hours) ✅ Done
   - Step-by-step migration
   - Before/after examples
   - Common patterns
   - Troubleshooting

3. **API reference** (1-2 hours)
   - Document all new functions
   - Document deprecations
   - Document migration timeline

**Deliverables**:
- ✅ Updated README.md
- ✅ Updated CLAUDE.md
- ✅ Migration guide
- ✅ API docs

### Phase 5: Examples and Polish (Week 3)
**Goal**: Real-world examples and polish

1. **Create examples** (3-4 hours)
   - Counter example
   - Auth example
   - Shopping cart example
   - LiveView example

2. **Polish** (2-3 hours)
   - Code review
   - Performance optimization
   - Error handling
   - Edge cases

3. **Final testing** (2-3 hours)
   - Integration tests
   - Performance tests
   - Load tests

**Deliverables**:
- ✅ Example applications
- ✅ All tests passing
- ✅ Performance benchmarks

## Detailed Implementation: :process Macro

### Current Macro
```elixir
defmacro __using__(:process) do
  quote do
    use GenServer

    def start_link(opts) do
      arg = Keyword.get(opts, :arg, %{})
      name = Keyword.get(opts, :name)
      GenServer.start_link(__MODULE__, arg, name: name)
    end

    def get_session_id do
      # ... existing implementation
    end
  end
end
```

### Enhanced Macro
```elixir
defmacro __using__(:process) do
  quote location: :keep do
    use GenServer
    require Logger

    # Existing start_link...

    # NEW: Default init with Redux infrastructure
    @impl true
    def init(arg) do
      # Call user's init if defined
      initial_app_state = if function_exported?(__MODULE__, :user_init, 1) do
        __MODULE__.user_init(arg)
      else
        %{}
      end

      # Build Redux infrastructure
      state = %{
        app_state: initial_app_state,
        _redux: %{
          reducers: %{},
          selectors: %{},
          subscriptions: [],
          middleware: [],
          history: [],
          max_history_size: 100
        }
      }

      {:ok, state}
    end

    # NEW: User-defined init (optional)
    def user_init(_arg), do: %{}
    defoverridable user_init: 1

    # NEW: Handle synchronous dispatch
    @impl true
    def handle_call({:dispatch, action}, _from, state) do
      try do
        {new_app_state, updated_redux} =
          __redux_dispatch__(action, state.app_state, state._redux)

        new_state = %{state |
          app_state: new_app_state,
          _redux: updated_redux
        }

        # Emit telemetry
        emit_dispatch_telemetry(action, state.app_state, new_app_state)

        {:reply, {:ok, new_app_state}, new_state}
      rescue
        error ->
          Logger.error("Dispatch error: #{inspect(error)}")
          {:reply, {:error, error}, state}
      end
    end

    # NEW: Handle asynchronous dispatch
    @impl true
    def handle_cast({:dispatch, action}, state) do
      try do
        {new_app_state, updated_redux} =
          __redux_dispatch__(action, state.app_state, state._redux)

        new_state = %{state |
          app_state: new_app_state,
          _redux: updated_redux
        }

        # Emit telemetry
        emit_dispatch_telemetry(action, state.app_state, new_app_state)

        {:noreply, new_state}
      rescue
        error ->
          Logger.error("Dispatch error: #{inspect(error)}")
          {:noreply, state}
      end
    end

    # NEW: Handle subscribe
    @impl true
    def handle_call({:subscribe, selector, pid, event_name}, _from, state) do
      try do
        {sub_id, updated_redux} =
          __redux_subscribe__(selector, pid, event_name, state.app_state, state._redux)

        new_state = %{state | _redux: updated_redux}

        {:reply, {:ok, sub_id}, new_state}
      rescue
        error ->
          Logger.error("Subscribe error: #{inspect(error)}")
          {:reply, {:error, error}, state}
      end
    end

    # NEW: Handle unsubscribe
    @impl true
    def handle_call({:unsubscribe, sub_id}, _from, state) do
      updated_redux = __redux_unsubscribe__(sub_id, state._redux)
      {:reply, :ok, %{state | _redux: updated_redux}}
    end

    # NEW: Handle register_reducer
    @impl true
    def handle_call({:register_reducer, name, reducer_fn}, _from, state) do
      updated_redux = put_in(state._redux.reducers[name], reducer_fn)
      {:reply, :ok, %{state | _redux: updated_redux}}
    end

    # NEW: Handle register_middleware
    @impl true
    def handle_call({:register_middleware, name, middleware_fn}, _from, state) do
      updated_redux = update_in(state._redux.middleware, &[{name, middleware_fn} | &1])
      {:reply, :ok, %{state | _redux: updated_redux}}
    end

    # NEW: Handle get_state
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
      updated_redux = __redux_remove_by_monitor__(ref, state._redux)
      {:noreply, %{state | _redux: updated_redux}}
    end

    # Existing get_session_id...

    # NEW: Redux dispatch implementation
    defp __redux_dispatch__(action, app_state, redux) do
      # Apply all registered reducers in sequence
      new_app_state = Enum.reduce(redux.reducers, app_state, fn {_name, reducer}, acc ->
        try do
          reducer.(acc, action)
        rescue
          error ->
            Logger.error("Reducer error: #{inspect(error)}")
            acc
        end
      end)

      # Apply middleware if any
      final_app_state = apply_middleware(action, app_state, new_app_state, redux.middleware)

      # Add to history
      history_entry = %{
        action: action,
        timestamp: System.system_time(:millisecond)
      }

      new_history = [history_entry | redux.history]
        |> Enum.take(redux.max_history_size)

      # Notify subscriptions
      updated_subscriptions = __redux_notify_subscriptions__(
        redux.subscriptions,
        app_state,
        final_app_state
      )

      updated_redux = %{redux |
        subscriptions: updated_subscriptions,
        history: new_history
      }

      {final_app_state, updated_redux}
    end

    # NEW: Redux subscribe implementation
    defp __redux_subscribe__(selector, pid, event_name, app_state, redux) do
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

    # NEW: Redux unsubscribe implementation
    defp __redux_unsubscribe__(sub_id, redux) do
      # Find and demonitor
      subscription = Enum.find(redux.subscriptions, &(&1.id == sub_id))

      if subscription do
        Process.demonitor(subscription.monitor_ref, [:flush])
      end

      # Remove from list
      updated_subscriptions = Enum.reject(redux.subscriptions, &(&1.id == sub_id))

      %{redux | subscriptions: updated_subscriptions}
    end

    # NEW: Notify all subscriptions
    defp __redux_notify_subscriptions__(subscriptions, _old_state, new_state) do
      Enum.map(subscriptions, fn sub ->
        try do
          new_value = sub.selector.(new_state)

          if new_value != sub.last_value do
            send(sub.pid, {sub.event_name, new_value})
            %{sub | last_value: new_value}
          else
            sub
          end
        rescue
          error ->
            Logger.error("Selector error: #{inspect(error)}")
            sub
        end
      end)
    end

    # NEW: Remove subscription by monitor ref
    defp __redux_remove_by_monitor__(monitor_ref, redux) do
      updated_subscriptions = Enum.reject(redux.subscriptions, &(&1.monitor_ref == monitor_ref))
      %{redux | subscriptions: updated_subscriptions}
    end

    # NEW: Apply middleware
    defp apply_middleware(_action, _old_state, new_state, []), do: new_state

    defp apply_middleware(action, old_state, new_state, middleware) do
      # Middleware can transform or observe state transitions
      Enum.reduce(middleware, new_state, fn {_name, mw_fn}, acc ->
        try do
          mw_fn.(action, old_state, acc)
        rescue
          error ->
            Logger.error("Middleware error: #{inspect(error)}")
            acc
        end
      end)
    end

    # NEW: Telemetry
    defp emit_dispatch_telemetry(action, old_state, new_state) do
      :telemetry.execute(
        [:phoenix, :session_process, :dispatch],
        %{duration: 0},
        %{action: action, old_state: old_state, new_state: new_state}
      )
    end

    defoverridable [
      init: 1,
      handle_call: 3,
      handle_cast: 2,
      handle_info: 2
    ]
  end
end
```

## Risk Mitigation

### Risk 1: Breaking Changes
**Mitigation**:
- All new code is additive
- Old Redux API continues to work
- Gradual deprecation over 3-6 months
- Comprehensive migration guide

### Risk 2: Performance Impact
**Mitigation**:
- Benchmark before/after
- Optimize hot paths
- Use ETS for large histories
- Profile with :fprof

### Risk 3: Edge Cases
**Mitigation**:
- Comprehensive test suite
- Test with existing applications
- Community beta testing period
- Detailed error messages

### Risk 4: Learning Curve
**Mitigation**:
- Excellent documentation
- Migration examples
- Video tutorials
- Active support in GitHub

## Success Criteria

- ✅ All existing tests pass
- ✅ New tests achieve >95% coverage
- ✅ Old Redux API still works with deprecation warnings
- ✅ New API is 50% less code for common cases
- ✅ Performance is equal or better
- ✅ Migration guide is clear and complete
- ✅ Zero breaking changes in v0.6.0

## Timeline Summary

| Week | Phase | Deliverables |
|------|-------|--------------|
| 1 | Core + Deprecation | Updated SessionProcess, Redux deprecation |
| 2 | LiveView + Docs | Updated LiveView integration, migration guide |
| 3 | Examples + Polish | Examples, final testing, release prep |

**Total Estimated Time**: 3 weeks (full-time) or 6 weeks (part-time)

## Next Steps

1. **Review this plan** with team/maintainers
2. **Create feature branch**: `feature/native-redux`
3. **Start Phase 1**: Core SessionProcess updates
4. **Iterate based on feedback**
5. **Beta release**: v0.6.0-rc.1
6. **Final release**: v0.6.0

## Notes

- Keep backward compatibility as top priority
- Document every breaking change (even if none expected)
- Get community feedback early and often
- Consider beta period for large users
- Plan for v1.0.0 to remove Redux module entirely

---

**Status**: ✅ Planning Complete - Ready for Implementation

**Last Updated**: 2025-10-29
