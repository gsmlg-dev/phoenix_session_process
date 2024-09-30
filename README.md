# Phoenix.SessionProcess

Create a process for each session, all user requests would through this process.

* [Github Repo](https://github.com/gsmlg-dev/phoenix_session_process)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `phoenix_session_process` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_session_process, "~> 0.3.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/phoenix_session_process>.


## How to

Add superviser to process tree

```elixir
    [
      ...
      {Phoenix.SessionProcess.Supervisor, []}
    ]
```

Add this after the `:fetch_session` plug to generate a unique session ID.

```elixir
    plug :fetch_session
    plug Phoenix.SessionProcess.SessionId
```

Start a session process with a session ID.

```elixir
    Phoenix.SessionProcess.start("session_id")
```

This will start a session process using the module defined with

```elixir
    config :phoenix_session_process, session_process: MySessionProcess
```

Define MySessionProcess

```elixir
defmodule MySessionProcess do
  @doc """
  The use macro is expanded as

      use GenServer

      def start_link(name: name, arg: arg) do
        GenServer.start_link(__MODULE__, arg, name: name)
      end
      def start_link(name: name) do
        GenServer.start_link(__MODULE__, %{}, name: name)
      end
  """
  use Phoenix.SessionProcess, :process
end

# with monitor live view
defmodule MySessionProcessWithMonitor do
  @doc """
  The use macro is expanded as

      use GenServer

      def start_link(name: name, arg: arg) do
        GenServer.start_link(__MODULE__, arg, name: name)
      end
      def start_link(name: name) do
        GenServer.start_link(__MODULE__, %{}, name: name)
      end

      @impl true
      def init(arg) do
        Process.flag(:trap_exit, true)

        {:ok, state}
      end

      @impl true
      def handle_call(:get_state, _from, state) do
        {:reply, state, state}
      end

      @impl true
      def handle_cast({:monitor, pid}, state) do
        state = state |> Map.update(:__live_view__, [pid], fn views -> [pid | views] end)
        Process.monitor(pid)
        {:noreply, state}
      end

      @impl true
      def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
        state = state |> Map.update(:__live_view__, [], fn views -> views |> Enum.filter(&(&1 != pid)) end)

        {:noreply, state}
      end

      @impl true
      def terminate(reason, state) do
        state
        |> Map.get(:__live_view__, [])
        |> Enum.each(&Process.send_after(&1, :session_expired, 0))
      end

  In live view

      def mount(_params, %{"session_id" => session_id} = _session, socket) do
        socket = socket
        |> assign(:session_id, session_id)

        Phoenix.SessionProcess.cast(session_id, {:monitor, self()})

        {:ok, socket}
      end

      # trap session expires
      def handle_info(:session_expired, socket) do
        {:noreply, socket |> redirect(to: @sign_in_page)}
      end
  """
  use Phoenix.SessionProcess, :process
end
```

Or you can start a session process with a specific module.

```elixir
    Phoenix.SessionProcess.start("session_id", MySessionProcess)
    # or
    Phoenix.SessionProcess.start("session_id", MySessionProcess, arg)
```

Check if a session process is started.

```elixir
    Phoenix.SessionProcess.started?("session_id")
```

Terminate a session process.

```elixir
    Phoenix.SessionProcess.terminate("session_id")
```

Genserver call on a session process.

```elixir
    Phoenix.SessionProcess.call("session_id", request)
```

Genserver cast on a session process.

```elixir
    Phoenix.SessionProcess.cast("session_id", request)
```

Get session id in SessionProcess.

```elixir
    get_session_id()
```

