defmodule Phoenix.SessionProcess.DefaultSessionProcess do
  @moduledoc """
  Default session process implementation providing basic key-value storage.

  This module serves as the default session process when no custom session module
  is specified. It provides a simple key-value store interface that can be used for
  basic session state management without requiring custom implementation.

  ## Features

  ### Simple Key-Value Storage
  - Store any Elixir term with a binary key
  - Retrieve values by key
  - Delete keys from the session state
  - Support for complex data structures

  ### Process Communication
  - `call/2` operations for synchronous requests
  - `cast/2` operations for asynchronous updates
  - Echo and ping functionality for testing

  ## Public API

  ### Call Operations
  - `:ping` - Returns `:pong` (useful for health checks)
  - `:get_state` - Returns the complete session state map
  - `{:sleep, duration}` - Sleeps for specified milliseconds (testing)
  - Any other request - Echoes the request back

  ### Cast Operations
  - `{:put, key, value}` - Stores a value with the given key
  - `{:delete, key}` - Removes the key from the session state
  - Any other cast - No-op (ignored)

  ## Usage Examples

  ### Basic Operations

      # Store data in session
      Phoenix.SessionProcess.cast(session_id, {:put, :user_id, 123})
      Phoenix.SessionProcess.cast(session_id, {:put, :preferences, %{theme: :dark}})

      # Retrieve session state
      {:ok, state} = Phoenix.SessionProcess.call(session_id, :get_state)
      # => {:ok, %{user_id: 123, preferences: %{theme: :dark}}}

      # Delete data from session
      Phoenix.SessionProcess.cast(session_id, {:delete, :user_id})

  ### Health Check

      # Check if session process is responsive
      {:ok, :pong} = Phoenix.SessionProcess.call(session_id, :ping)

  ### Testing

      # Simulate slow operations
      {:ok, :ok} = Phoenix.SessionProcess.call(session_id, {:sleep, 1000})

  ## Default Session Module

  This module is used automatically when no custom session module is specified
  in the configuration:

      # Uses DefaultSessionProcess
      Phoenix.SessionProcess.start("session_123")

      # Uses custom module
      Phoenix.SessionProcess.start("session_123", MyApp.CustomSessionProcess)

  ## Limitations

  - Simple key-value storage (no complex queries)
  - No data validation or type checking
  - No persistence across application restarts
  - No built-in security or access controls

  ## Custom Implementation

  For more advanced use cases, create a custom session process:

      defmodule MyApp.SessionProcess do
        use Phoenix.SessionProcess, :process

        @impl true
        def init(_init_arg) do
          {:ok, %{user: nil, cart: [], preferences: %{}}}
        end

        @impl true
        def handle_call(:get_user, _from, state) do
          {:reply, state.user, state}
        end

        @impl true
        def handle_cast({:set_user, user}, state) do
          {:noreply, %{state | user: user}}
        end
      end

  Then configure it as the default:

      config :phoenix_session_process,
        session_process: MyApp.SessionProcess
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
