defmodule Phoenix.SessionProcess.Supervisor do
  @moduledoc """
  Top-level supervisor for the Phoenix.SessionProcess system.

  This supervisor manages the core infrastructure components required for session
  process management. It must be added to your application's supervision tree to
  enable session process functionality.

  ## Supervision Tree Structure

  The supervisor manages three key children:

  ### 1. Registry
  - **Name**: `Phoenix.SessionProcess.Registry`
  - **Purpose**: Maintains a registry of all active session processes for fast lookups
  - **Keys**: `:unique` - Ensures each session ID maps to exactly one process

  ### 2. ProcessSupervisor
  - **Module**: `Phoenix.SessionProcess.ProcessSupervisor`
  - **Purpose**: Dynamic supervisor that manages individual session processes
  - **Strategy**: `:one_for_one` - Restarts failed session processes independently

  ### 3. Cleanup Process
  - **Module**: `Phoenix.SessionProcess.Cleanup`
  - **Purpose**: Periodically cleans up expired session processes based on TTL
  - **Strategy**: Runs cleanup tasks at regular intervals

  ## Integration

  Add this supervisor to your application's supervision tree in `lib/my_app/application.ex`:

      def start(_type, _args) do
        children = [
          # ... other children ...
          {Phoenix.SessionProcess, []}
          # Or with runtime configuration:
          {Phoenix.SessionProcess, [
            session_process: MyApp.CustomProcess,
            max_sessions: 20_000,
            session_ttl: :timer.hours(2),
            rate_limit: 150
          ]}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  ## Runtime Configuration

  Configuration can be provided at supervisor startup, overriding application environment settings:

  - `:session_process` - Default session module to use
  - `:max_sessions` - Maximum concurrent sessions allowed
  - `:session_ttl` - Session time-to-live in milliseconds
  - `:rate_limit` - Maximum session creations per minute

  Runtime configuration takes precedence over application environment configuration.

  ## Process Lifecycle

  1. **Application Start**: Top-level supervisor starts all children
  2. **Session Creation**: ProcessSupervisor dynamically creates session processes
  3. **Registry Registration**: Each session process is registered in the Registry
  4. **Periodic Cleanup**: Cleanup process removes expired sessions
  5. **Failure Handling**: Failed session processes are restarted independently

  ## Error Handling

  The supervisor uses the `:one_for_one` strategy, which means:
  - If a child process crashes, only that child is restarted
  - Other children continue running unaffected
  - This provides isolation between different components

  ## Monitoring

  All child processes are registered and can be monitored:

      # Check if supervisor is running
      Process.whereis(Phoenix.SessionProcess.Supervisor)

      # Check registry status
      Registry.info(Phoenix.SessionProcess.Registry)
  """

  require Logger

  # Automatically defines child_spec/1
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    # Store runtime configuration in ETS for fast access
    # This allows configuration to be passed at startup instead of only via application env
    runtime_config = normalize_config(init_arg)

    if runtime_config != [] do
      # Create ETS table for runtime config (public, readable by all processes)
      :ets.new(:phoenix_session_process_runtime_config, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

      # Store each config option in ETS
      Enum.each(runtime_config, fn {key, value} ->
        :ets.insert(:phoenix_session_process_runtime_config, {key, value})
      end)
    end

    children = [
      {Registry, keys: :unique, name: Phoenix.SessionProcess.Registry},
      {Phoenix.SessionProcess.ProcessSupervisor, []},
      {Phoenix.SessionProcess.RateLimiter, []},
      {Phoenix.SessionProcess.Cleanup, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Normalize and validate configuration options
  defp normalize_config(opts) when is_list(opts) do
    valid_keys = [:session_process, :max_sessions, :session_ttl, :rate_limit]

    opts
    |> Enum.filter(fn {key, _value} -> key in valid_keys end)
    |> Enum.into(%{})
    |> Map.to_list()
  end

  defp normalize_config(_), do: []
end
