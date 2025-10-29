defmodule TestProcess do
  @moduledoc """
  Test helper module for session process testing.

  This module provides a simple session process implementation used in tests
  to verify session process functionality, state management, and lifecycle operations.

  Uses standard GenServer state management (no Agent).
  """

  use Phoenix.SessionProcess, :process

  @impl true
  def init(init_arg \\ %{}) do
    {:ok, Map.put_new(init_arg, :value, 0)}
  end

  @impl true
  def handle_call(:get_value, _from, state) do
    {:reply, Map.get(state, :value), state}
  end

  @impl true
  def handle_call(:get_my_session_id, _from, state) do
    {:reply, get_session_id(), state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:add_one, state) do
    value = Map.get(state, :value, 0)
    {:noreply, Map.put(state, :value, value + 1)}
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    {:noreply, Map.put(state, key, value)}
  end
end
