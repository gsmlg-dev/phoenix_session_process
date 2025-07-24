defmodule Phoenix.SessionProcess.State do
  @moduledoc """
  An agent to store session state with Redux-style state management support.

  This module provides both the traditional Agent-based state storage and
  Redux-style state management with actions and reducers.
  """
  use Agent

  @type state :: any()
  @type action :: any()
  @type reducer :: (state(), action() -> state())

  @doc """
  Starts the state agent with initial state.
  """
  @spec start_link(any()) :: {:ok, pid()} | {:error, any()}
  def start_link(initial_state \\ %{}) do
    Agent.start_link(fn -> initial_state end)
  end

  @doc """
  Gets a value from the state by key.
  """
  @spec get(pid(), any()) :: any()
  def get(pid, key) do
    Agent.get(pid, &Map.get(&1, key))
  end

  @doc """
  Puts a value into the state by key.
  """
  @spec put(pid(), any(), any()) :: :ok
  def put(pid, key, value) do
    Agent.update(pid, &Map.put(&1, key, value))
  end

  @doc """
  Gets the entire state.
  """
  @spec get_state(pid()) :: state()
  def get_state(pid) do
    Agent.get(pid, & &1)
  end

  @doc """
  Updates the entire state.
  """
  @spec update_state(pid(), (state() -> state())) :: :ok
  def update_state(pid, update_fn) do
    Agent.update(pid, update_fn)
  end

  @doc """
  Redux-style state dispatch using a reducer function or module.

  ## Examples

      iex> {:ok, pid} = State.start_link(%{count: 0})
      iex> State.dispatch(pid, {:increment, 1}, fn state, {:increment, val} -> %{state | count: state.count + val} end)
      iex> State.get_state(pid)
      %{count: 1}

      iex> {:ok, pid} = State.start_link(%{total: 0})
      iex> State.dispatch(pid, {:add, 5}, StateTest.TestStateReducer)
      iex> State.get_state(pid)
      %{total: 5}
  """
  @spec dispatch(pid(), action(), reducer() | module()) :: :ok
  def dispatch(pid, action, reducer) when is_function(reducer, 2) do
    Agent.update(pid, fn state -> reducer.(state, action) end)
  end

  def dispatch(pid, action, reducer_module) do
    Agent.update(pid, fn state -> reducer_module.reduce(state, action) end)
  end

  @doc """
  Resets the state to the initial value.
  """
  @spec reset(pid(), state()) :: :ok
  def reset(pid, initial_state \\ %{}) do
    Agent.update(pid, fn _ -> initial_state end)
  end
end
