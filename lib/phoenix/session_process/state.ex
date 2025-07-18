defmodule Phoenix.SessionProcess.State do
  @moduledoc """
  An agent to store session state.
  """
  use Agent

  def start_link(initial_state \\ %{}) do
    Agent.start_link(fn -> initial_state end)
  end

  def get(pid, key) do
    Agent.get(pid, &Map.get(&1, key))
  end

  def put(pid, key, value) do
    Agent.update(pid, &Map.put(&1, key, value))
  end

  def get_state(pid) do
    Agent.get(pid, & &1)
  end
end
