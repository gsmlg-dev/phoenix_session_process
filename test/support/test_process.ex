defmodule TestProcess do
  @moduledoc """
  Test helper module for session process testing.

  This module provides a simple session process implementation used in tests
  to verify session process functionality, state management, and lifecycle operations.

  Uses the Redux infrastructure provided by the :process macro.
  """

  use Phoenix.SessionProcess, :process

  @impl true
  def init_state(init_arg \\ %{}) do
    Map.put_new(init_arg, :value, 0)
  end

  @impl true
  def handle_call(:get_value, _from, state) do
    {:reply, Map.get(state.app_state, :value), state}
  end

  @impl true
  def handle_call(:get_my_session_id, _from, state) do
    {:reply, get_session_id(), state}
  end

  @impl true
  def handle_call(msg, from, state) do
    super(msg, from, state)
  end

  @impl true
  def handle_cast(:add_one, state) do
    value = Map.get(state.app_state, :value, 0)
    {:noreply, %{state | app_state: Map.put(state.app_state, :value, value + 1)}}
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    {:noreply, %{state | app_state: Map.put(state.app_state, key, value)}}
  end

  @impl true
  def handle_cast(msg, state) do
    super(msg, state)
  end
end
