defmodule TestProcess do
  @doc false

  use Phoenix.SessionProcess, :process

  @impl true
  def init(init_arg \\ %{}) do
    {:ok, init_arg}
  end

  @impl true
  def handle_call(:get_value, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:add_one, state) do
    {:noreply, state + 1}
  end
end
