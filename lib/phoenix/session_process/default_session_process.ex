defmodule Phoenix.SessionProcess.DefaultSessionProcess do
  @moduledoc """
  Default session process implementation.
  """
  use Phoenix.SessionProcess, :process

  @impl true
  def init(_init_arg) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:sleep, duration}, _from, state) do
    Process.sleep(duration)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(any, _from, state) do
    {:reply, any, state}
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    {:noreply, Map.put(state, key, value)}
  end

  @impl true
  def handle_cast({:delete, key}, state) do
    {:noreply, Map.delete(state, key)}
  end

  @impl true
  def handle_cast(_any, state) do
    {:noreply, state}
  end
end
