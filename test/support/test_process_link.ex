defmodule TestProcessLink do
  @moduledoc """
  Test helper module for session process with LiveView link testing.

  This module provides a session process implementation using the :process_link
  option to verify LiveView monitoring functionality and get_session_id behavior.
  """

  use Phoenix.SessionProcess, :process_link

  alias Phoenix.SessionProcess.State

  @impl true
  def init(init_arg \\ %{}) do
    {:ok, agent} = State.start_link(init_arg)
    {:ok, %{agent: agent}}
  end

  @impl true
  def handle_call(:get_value, _from, state) do
    {:reply, State.get(state.agent, :value), state}
  end

  @impl true
  def handle_call(:get_my_session_id, _from, state) do
    {:reply, get_session_id(), state}
  end

  @impl true
  def handle_cast(:add_one, state) do
    value = State.get(state.agent, :value)
    State.put(state.agent, :value, value + 1)
    {:noreply, state}
  end
end
