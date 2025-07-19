# Redux Migration Guide for Phoenix Session Process

This guide helps you migrate from traditional state management to Redux-style state management with actions and reducers.

## Overview

The Redux-style state management provides:
- **Predictable state updates** through actions and reducers
- **Time-travel debugging** with action history
- **Middleware support** for logging, validation, and side effects
- **State persistence** and replay capabilities
- **Better debugging** with action logging

## Quick Migration Steps

### 1. Add Redux Module

Add the Redux module to your session process:

```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process
  use Phoenix.SessionProcess.Redux
  
  # ... rest of your module
end
```

### 2. Implement Reducer Function

Define your reducer function that handles actions:

```elixir
defmodule MyApp.SessionProcess do
  # ... previous code ...
  
  @impl true
  def reducer(state, action) do
    case action do
      {:set_user, user} ->
        %{state | user: user}
      
      {:update_preferences, prefs} ->
        %{state | preferences: Map.merge(state.preferences, prefs)}
      
      {:add_to_cart, item} ->
        %{state | cart: [item | state.cart]}
      
      :clear_cart ->
        %{state | cart: []}
      
      :reset ->
        %{user: nil, preferences: %{}, cart: []}
      
      _ ->
        state
    end
  end
end
```

### 3. Update Initialization

Update your `init/1` function to use Redux state:

```elixir
@impl true
def init(_init_arg) do
  initial_state = %{
    user: nil,
    preferences: %{},
    cart: []
  }
  
  {:ok, %{redux: Redux.init_state(initial_state)}}
end
```

### 4. Update Message Handlers

Replace direct state manipulation with Redux dispatch:

**Before:**
```elixir
def handle_call(:get_user, _from, state) do
  {:reply, state.user, state}
end

def handle_cast({:set_user, user}, state) do
  {:noreply, %{state | user: user}}
end
```

**After:**
```elixir
def handle_call({:dispatch, :get_user}, _from, state) do
  current_user = Redux.current_state(state.redux).user
  {:reply, current_user, state}
end

def handle_cast({:dispatch, {:set_user, user}}, state) do
  new_redux = Redux.dispatch(state.redux, {:set_user, user})
  {:noreply, %{state | redux: new_redux}}
end
```

## Migration Patterns

### Pattern 1: Direct Replacement

Replace all state manipulation with Redux actions:

```elixir
defmodule MyApp.ShoppingCartProcess do
  use Phoenix.SessionProcess, :process
  use Phoenix.SessionProcess.Redux

  @impl true
  def init(_args) do
    {:ok, %{redux: Redux.init_state(%{items: [], total: 0})}}
  end

  @impl true
  def reducer(state, action) do
    case action do
      {:add_item, item} ->
        items = [item | state.items]
        total = Enum.reduce(items, 0, fn i, acc -> acc + i.price end)
        %{state | items: items, total: total}
      
      {:remove_item, item_id} ->
        items = Enum.reject(state.items, & &1.id == item_id)
        total = Enum.reduce(items, 0, fn i, acc -> acc + i.price end)
        %{state | items: items, total: total}
      
      :clear_cart ->
        %{items: [], total: 0}
      
      _ ->
        state
    end
  end

  # API functions
  def add_item(session_id, item) do
    Phoenix.SessionProcess.cast(session_id, {:dispatch, {:add_item, item}})
  end

  def remove_item(session_id, item_id) do
    Phoenix.SessionProcess.cast(session_id, {:dispatch, {:remove_item, item_id}})
  end

  def get_cart(session_id) do
    case Phoenix.SessionProcess.call(session_id, {:dispatch, :get_cart}) do
      {:ok, state} -> {:ok, state}
      error -> error
    end
  end
end
```

### Pattern 2: Middleware Integration

Add logging and validation middleware:

```elixir
defmodule MyApp.SessionProcess do
  use Phoenix.SessionProcess, :process
  use Phoenix.SessionProcess.Redux

  @impl true
  def init(_args) do
    initial_state = %{user: nil, preferences: %{}, cart: []}
    
    redux = Redux.init_state(initial_state)
    |> Redux.add_middleware(Redux.logger_middleware())
    |> Redux.add_middleware(Redux.validation_middleware(&valid_action?/1))
    
    {:ok, %{redux: redux}}
  end

  defp valid_action?({:set_user, user}) when is_map(user), do: true
  defp valid_action?({:add_to_cart, item}) when is_map(item), do: true
  defp valid_action?(:clear_cart), do: true
  defp valid_action?(_), do: false

  # ... rest of implementation
end
```

### Pattern 3: Time-Travel Debugging

Use action history for debugging:

```elixir
defmodule MyApp.DebugSessionProcess do
  use Phoenix.SessionProcess, :process
  use Phoenix.SessionProcess.Redux

  @impl true
  def init(_args) do
    {:ok, %{redux: Redux.init_state(%{count: 0}, max_history_size: 50)}}
  end

  @impl true
  def reducer(state, action) do
    case action do
      {:increment, value} -> %{state | count: state.count + value}
      {:decrement, value} -> %{state | count: state.count - value}
      :reset -> %{count: 0}
      _ -> state
    end
  end

  # Debug functions
  def get_history(session_id) do
    case Phoenix.SessionProcess.call(session_id, {:dispatch, :get_history}) do
      {:ok, redux} -> {:ok, Redux.history(redux)}
      error -> error
    end
  end

  def time_travel(session_id, steps_back) do
    case Phoenix.SessionProcess.call(session_id, {:dispatch, {:time_travel, steps_back}}) do
      {:ok, redux} -> {:ok, Redux.current_state(redux)}
      error -> error
    end
  end
end
```

## Testing Migration

### Test Helpers

Create test helpers to verify migration:

```elixir
defmodule MyApp.SessionTestHelpers do
  def assert_state_consistency(old_module, new_module, initial_state, actions) do
    # Test old approach
    old_result = simulate_old_state(old_module, initial_state, actions)
    
    # Test new approach
    new_result = simulate_new_state(new_module, initial_state, actions)
    
    assert old_result == new_result
  end

  defp simulate_old_state(module, initial_state, actions) do
    state = initial_state
    Enum.reduce(actions, state, fn action, acc ->
      case action do
        {:set_user, user} -> %{acc | user: user}
        {:add_to_cart, item} -> %{acc | cart: [item | acc.cart]}
        _ -> acc
      end
    end)
  end

  defp simulate_new_state(module, initial_state, actions) do
    redux = Redux.init_state(initial_state)
    Enum.reduce(actions, redux, fn action, acc ->
      Redux.dispatch(acc, action, &module.reducer/2)
    end)
    Redux.current_state(new_redux)
  end
end
```

### Migration Tests

```elixir
defmodule MyApp.SessionMigrationTest do
  use ExUnit.Case
  alias MyApp.{OldSessionProcess, NewSessionProcess}

  test "state consistency after migration" do
    initial_state = %{user: nil, cart: []}
    actions = [
      {:set_user, %{id: 1, name: "Alice"}},
      {:add_to_cart, %{id: 1, name: "Widget", price: 10}},
      {:add_to_cart, %{id: 2, name: "Gadget", price: 20}}
    ]

    MyApp.SessionTestHelpers.assert_state_consistency(
      OldSessionProcess,
      NewSessionProcess,
      initial_state,
      actions
    )
  end
end
```

## Action Patterns

### Common Action Types

```elixir
# User actions
{:user_login, user}
{:user_logout}
{:user_update, changes}

# Data actions
{:data_set, key, value}
{:data_delete, key}
{:data_merge, map}

# Collection actions
{:collection_add, collection_name, item}
{:collection_remove, collection_name, item_id}
{:collection_update, collection_name, item_id, changes}

# Session actions
{:session_start, session_data}
{:session_end}
{:session_timeout}

# UI actions
{:ui_update, page, changes}
{:ui_error, error_message}
{:ui_loading, boolean}
```

### Action Creators

Create helper functions for action creation:

```elixir
defmodule MyApp.SessionActions do
  def set_user(user), do: {:set_user, user}
  def add_to_cart(item), do: {:add_to_cart, item}
  def remove_from_cart(item_id), do: {:remove_from_cart, item_id}
  def update_preferences(prefs), do: {:update_preferences, prefs}
  def clear_cart, do: :clear_cart
end
```

## Performance Considerations

### Memory Usage
- Redux state includes action history
- Default history size: 100 actions
- Can be configured: `Redux.init_state(state, max_history_size: 50)`

### Serialization
- State should be serializable for persistence
- Avoid storing complex objects in state
- Use simple data structures (maps, lists, primitives)

## Migration Checklist

- [ ] Add `use Phoenix.SessionProcess.Redux` to session processes
- [ ] Implement `reducer/2` function
- [ ] Update `init/1` to use Redux state structure
- [ ] Update message handlers to use Redux dispatch
- [ ] Add migration tests for state consistency
- [ ] Update documentation and team guidelines
- [ ] Monitor memory usage with action history
- [ ] Consider middleware for logging/validation
- [ ] Plan gradual rollout strategy
- [ ] Prepare rollback plan

## Support

For migration support:
1. Check the `Phoenix.SessionProcess.MigrationExamples` module for detailed examples
2. Run existing tests to ensure compatibility
3. Use the test helpers provided in this guide
4. Monitor telemetry events during migration
5. Start with non-critical sessions first

## Backward Compatibility

The Redux module is designed to be backward compatible:
- Existing session processes continue to work unchanged
- New features are opt-in via `use Phoenix.SessionProcess.Redux`
- Migration can be done gradually
- No breaking changes to existing APIs