# Test Migration Notes for Redux-Only Architecture

This document outlines the changes needed to test files after the Redux-only refactoring.

## Files Requiring Updates

### 1. test/phoenix/session_process/live_view_test.exs

**Current State**: Tests the manual `broadcast_state_change` pattern with `:get_state` message.

**Required Changes**:
- Update test session process to use Redux:
  ```elixir
  defmodule TestLiveViewProcess do
    use Phoenix.SessionProcess, :process
    alias Phoenix.SessionProcess.Redux

    @impl true
    def init(init_arg) do
      redux = Redux.init_state(init_arg,
        pubsub: TestPubSub,
        pubsub_topic: "session:#{get_session_id()}:redux"
      )
      {:ok, %{redux: redux}}
    end

    @impl true
    def handle_call(:get_redux_state, _from, state) do
      {:reply, {:ok, state.redux}, state}
    end

    @impl true
    def handle_cast({:put, key, value}, state) do
      new_redux = Redux.dispatch(state.redux, {:put, key, value}, &reducer/2)
      {:noreply, %{state | redux: new_redux}}
    end

    defp reducer(state, {:put, key, value}) do
      Map.put(state, key, value)
    end
  end
  ```

- Update `mount_session/3` calls: Default `state_key` is now `:get_redux_state`
- Update PubSub topic: Change from `"session:#{session_id}:state"` to `"session:#{session_id}:redux"`
- Update message format: Change from `{:session_state_change, state}` to `{:redux_state_change, %{state: state, action: action, timestamp: timestamp}}`
- Update `session_topic/1` assertions: Should return `"session:user_123:redux"` not `"session:user_123:state"`

**Specific Test Updates**:
- Line 62: Change default `state_key` from `:get_state` to `:get_redux_state`
- Line 87: Update to expect Redux topic: `"session:#{session_id}:redux"`
- Line 123: Test custom Redux state key like `:get_custom_redux_state`
- Line 242: Update topic assertion to `"session:#{session_id}:redux"`
- All `assert_receive` calls: Change message format to `{:redux_state_change, %{state: _}}`

### 2. test/phoenix/session_process/live_view_integration_test.exs

**Current State**: Tests full integration with manual `broadcast_state_change`.

**Required Changes**:
- Update `IntegrationSessionProcess` to use Redux (similar pattern as above)
- Update all `broadcast_state_change` calls to `Redux.dispatch` calls
- Change message handling in tests:
  ```elixir
  # OLD:
  def handle_info({:session_state_change, new_state}, socket) do
    send(parent, {:state_updated, self(), new_state})
    receive_loop(socket, parent)
  end

  # NEW:
  def handle_info({:redux_state_change, %{state: new_state}}, socket) do
    send(parent, {:state_updated, self(), new_state})
    receive_loop(socket, parent)
  end
  ```

- Update all PubSub subscriptions: `"session:#{session_id}:state"` → `"session:#{session_id}:redux"`
- Update all message format assertions throughout tests

**Specific Test Updates**:
- Lines 12-45: Rewrite `IntegrationSessionProcess` to use Redux
- Line 54: `mount_session` will need Redux state key
- Lines 69, 87, 132, 157, etc.: All `{:session_state_change, ...}` → `{:redux_state_change, %{state: ...}}`
- Lines 326, 339: Update PubSub topic subscriptions
- Lines 376-380: Update broadcast message format assertions

### 3. test/phoenix/session_process/pubsub_broadcast_test.exs

**Status**: DELETED - This file tested the manual `broadcast_state_change` helpers which no longer exist.

## Testing Strategy Recommendations

1. **Create Redux Test Helper Module**: Create a reusable test helper that provides a standard Redux session process for tests.

2. **Test Redux Integration**: Add new tests specifically for:
   - Redux state initialization with PubSub
   - Redux dispatch triggering PubSub broadcasts
   - Redux message format correctness
   - Redux selector integration (if used)

3. **Test Message Format**: Verify the Redux message format includes:
   - `state`: The current state
   - `action`: The action that was dispatched
   - `timestamp`: When the action occurred

4. **Test Topic Naming**: Ensure Redux topics follow the pattern `"session:#{session_id}:redux"`

## Example Redux Test Session Process

```elixir
defmodule TestReduxSessionProcess do
  use Phoenix.SessionProcess, :process
  alias Phoenix.SessionProcess.Redux

  @impl true
  def init(init_state) do
    redux = Redux.init_state(
      init_state,
      pubsub: TestPubSub,
      pubsub_topic: "session:#{get_session_id()}:redux"
    )
    {:ok, %{redux: redux}}
  end

  @impl true
  def handle_call(:get_redux_state, _from, state) do
    {:reply, {:ok, state.redux}, state}
  end

  @impl true
  def handle_call({:dispatch, action}, _from, state) do
    new_redux = Redux.dispatch(state.redux, action, &reducer/2)
    {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
  end

  @impl true
  def handle_cast({:dispatch_async, action}, state) do
    new_redux = Redux.dispatch(state.redux, action, &reducer/2)
    {:noreply, %{state | redux: new_redux}}
  end

  defp reducer(state, action) do
    case action do
      {:set, key, value} -> Map.put(state, key, value)
      {:increment, key} -> Map.update(state, key, 1, &(&1 + 1))
      _ -> state
    end
  end
end
```

## Migration Checklist

- [ ] Update all test session processes to use Redux
- [ ] Change all `:get_state` to `:get_redux_state`
- [ ] Update all PubSub topic patterns
- [ ] Update all message format assertions
- [ ] Remove tests for deleted `broadcast_state_change` helper
- [ ] Remove tests for deleted `session_topic/0` helper (from session process, not LiveView module)
- [ ] Add tests for Redux-specific features
- [ ] Verify all tests pass with new architecture

## Notes

- The Redux `get_state/1` function extracts the `current_state` from the Redux struct
- LiveView's `mount_session/3` now automatically extracts state from Redux struct
- All state updates must go through `Redux.dispatch/3`
- PubSub broadcasting is automatic when Redux is configured with `pubsub` and `pubsub_topic`
