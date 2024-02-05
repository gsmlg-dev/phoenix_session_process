# Phoenix.SessionProcess

Create a process for each session, all user requests would through this process.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `phoenix_session_process` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_session_process, "~> 0.1.0"}
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

