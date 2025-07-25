defmodule Phoenix.SessionProcess.MigrationExamples do
  @moduledoc """
  Migration examples for transitioning to Redux-style state management.

  This module provides comprehensive examples showing how to migrate from
  traditional state management to Redux-style actions and reducers.
  """

  @doc """
  Returns documentation for traditional state management approach.
  """
  def old_approach_docs do
    """
    Traditional State Management (Legacy):

    The traditional approach uses direct state manipulation with handle_call and handle_cast:

    defmodule MyApp.OldSessionProcess do
      use Phoenix.SessionProcess, :process

      @impl true
      def init(_init_arg) do
        {:ok, %{user: nil, preferences: %{}, cart: []}}
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
    """
  end

  @doc """
  Returns documentation for Redux-style state management approach.
  """
  def new_approach_docs do
    """
    Redux-Style State Management (New):

    The Redux approach uses actions and reducers for predictable state updates:

    defmodule MyApp.NewSessionProcess do
      use Phoenix.SessionProcess, :process
      use Phoenix.SessionProcess.Redux

      @impl true
      def init(_init_arg) do
        initial_state = %{user: nil, preferences: %{}, cart: []}
        {:ok, %{redux: Redux.init_state(initial_state)}}
      end

      @impl true
      def reducer(state, action) do
        case action do
          {:set_user, user} ->
            %{state | user: user}
          {:add_to_cart, item} ->
            %{state | cart: [item | state.cart]}
          :clear_cart ->
            %{state | cart: []}
          _ ->
            state
        end
      end

      @impl true
      def handle_call({:dispatch, action}, _from, state) do
        new_redux_state = Redux.dispatch(state.redux, action)
        {:reply, {:ok, Redux.current_state(new_redux_state)}, %{state | redux: new_redux_state}}
      end
    end
    """
  end

  @doc """
  Returns migration strategies documentation.
  """
  def migration_strategies_docs do
    """
    Migration Strategies:

    1. Gradual Migration: Add Redux alongside existing state management
    2. Wrapper Module: Create a wrapper that provides both interfaces
    3. Adapter Pattern: Use an adapter to translate between patterns

    Recommended approach is gradual migration for backward compatibility.
    """
  end

  @doc """
  Returns action patterns documentation.
  """
  def action_patterns_docs do
    """
    Common Action Patterns:

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

    # Reset actions
    :reset_all
    {:reset_key, key}
    """
  end

  @doc """
  Returns the migration checklist.
  """
  def migration_checklist do
    [
      "Backup existing state: Ensure you can rollback if needed",
      "Add Redux module: Include `use Phoenix.SessionProcess.Redux`",
      "Implement reducer: Define `reducer/2` function",
      "Update init: Initialize Redux state structure",
      "Add action handlers: Handle {:dispatch, action} messages",
      "Test thoroughly: Compare old vs new state behavior",
      "Gradual rollout: Use feature flags for gradual migration",
      "Monitor: Track state consistency and performance",
      "Cleanup: Remove legacy code once migration is complete",
      "Document: Update team on new patterns and best practices"
    ]
  end
end
