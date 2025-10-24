defmodule TestProcess do
  @moduledoc """
  Test helper module for session process testing.

  This module provides a simple session process implementation used in tests
  to verify session process functionality, state management, and lifecycle operations.
  """

  use Phoenix.SessionProcess, :process

  @impl true
  def init(init_arg \\ %{}) do
    {:ok, agent} = Phoenix.SessionProcess.State.start_link(init_arg)
    {:ok, %{agent: agent}}
  end

  @impl true
  def handle_call(:get_value, _from, state) do
    {:reply, Phoenix.SessionProcess.State.get(state.agent, :value), state}
  end

  @impl true
  def handle_cast(:add_one, state) do
    value = Phoenix.SessionProcess.State.get(state.agent, :value)
    Phoenix.SessionProcess.State.put(state.agent, :value, value + 1)
    {:noreply, state}
  end
end
