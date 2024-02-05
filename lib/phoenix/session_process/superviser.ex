defmodule Phoenix.SessionProcess.Supervisor do
  require Logger

  # Automatically defines child_spec/1
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: Phoenix.SessionProcess.Registry},
      {Phoenix.SessionProcess.ProcessSupervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
