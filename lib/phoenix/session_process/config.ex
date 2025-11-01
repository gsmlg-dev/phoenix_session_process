defmodule Phoenix.SessionProcess.Config do
  @moduledoc """
  Configuration management for Phoenix.SessionProcess.

  This module provides access to all configurable aspects of the session process library.
  Configuration is done through application environment variables and can be set in your
  `config/config.exs` file.

  ## Configuration Options

  All configuration is done under the `:phoenix_session_process` application key:

  ```elixir
  config :phoenix_session_process,
    session_process: MyApp.SessionProcess,  # Default session module
    max_sessions: 10_000,                   # Maximum concurrent sessions
    session_ttl: 3_600_000,                # Session TTL in milliseconds (1 hour)
    rate_limit: 100,                       # Sessions per minute limit
    unmatched_action_handler: :log         # How to handle unmatched actions (:log, :warn, :silent, or custom function)
  ```

  ## Options

  ### `:session_process`
  - **Type**: `module()`
  - **Default**: `Phoenix.SessionProcess.DefaultSessionProcess`
  - **Description**: The default module to use when creating session processes without specifying a module

  ### `:max_sessions`
  - **Type**: `integer()`
  - **Default**: `10_000`
  - **Description**: Maximum number of concurrent sessions allowed. Helps prevent memory exhaustion.

  ### `:session_ttl`
  - **Type**: `integer()`
  - **Default**: `3_600_000` (1 hour in milliseconds)
  - **Description**: Time-to-live for idle sessions. Sessions are automatically cleaned up after this period.

  ### `:rate_limit`
  - **Type**: `integer()`
  - **Default**: `100`
  - **Description**: Maximum number of new sessions that can be created per minute. Prevents abuse.

  ### `:unmatched_action_handler`
  - **Type**: `:log | :warn | :silent | (action, reducer_module, reducer_name -> any())`
  - **Default**: `:log`
  - **Description**: How to handle actions that don't match any pattern in a reducer's `handle_action/2`:
    - `:log` - Log debug message suggesting use of action prefix
    - `:warn` - Log warning message (useful for debugging)
    - `:silent` - No logging
    - Custom function with arity 3: `fun(action, reducer_module, reducer_name)`

  ## Runtime Configuration

  Configuration can be provided in two ways:

  ### 1. Application Environment (config files)

      # config/config.exs
      config :phoenix_session_process,
        session_process: MyApp.SessionProcess,
        max_sessions: 10_000

  ### 2. Supervisor Start Options (runtime)

      # lib/my_app/application.ex
      def start(_type, _args) do
        children = [
          {Phoenix.SessionProcess, [
            session_process: MyApp.SessionProcess,
            max_sessions: 20_000,
            session_ttl: :timer.hours(2),
            rate_limit: 150
          ]}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  **Priority**: Runtime options (passed to supervisor) take precedence over application environment.

  ## Environment-specific Configuration

  Different environments can have different configurations:

      # config/dev.exs
      config :phoenix_session_process,
        session_ttl: :timer.hours(8)  # Longer TTL for development

      # config/prod.exs
      config :phoenix_session_process,
        max_sessions: 50_000,         # Higher limit for production
        session_ttl: :timer.minutes(30)  # Shorter TTL for production
  """

  @default_session_process Phoenix.SessionProcess.DefaultSessionProcess
  @default_max_sessions 10_000
  # 1 hour in milliseconds
  @default_session_ttl 3_600_000
  # sessions per minute
  @default_rate_limit 100
  @default_unmatched_action_handler :log

  @doc """
  Returns the configured default session process module.

  ## Examples

      iex> module = Phoenix.SessionProcess.Config.session_process()
      iex> is_atom(module)
      true

  ## Returns

  - `module()` - The configured session process module, or `Phoenix.SessionProcess.DefaultSessionProcess` if not configured

  ## Configuration

  Set in your config file:

      config :phoenix_session_process,
        session_process: MyApp.CustomSessionProcess
  """
  @spec session_process :: module()
  def session_process do
    get_config(:session_process, @default_session_process)
  end

  @doc """
  Returns the maximum number of allowed concurrent sessions.

  ## Examples

      iex> max = Phoenix.SessionProcess.Config.max_sessions()
      iex> is_integer(max)
      true
      iex> max > 0
      true

  ## Returns

  - `integer()` - Maximum concurrent sessions allowed (default: 10,000)

  ## Configuration

  Set in your config file:

      config :phoenix_session_process,
        max_sessions: 50_000
  """
  @spec max_sessions :: integer()
  def max_sessions do
    get_config(:max_sessions, @default_max_sessions)
  end

  @doc """
  Returns the session time-to-live (TTL) in milliseconds.

  ## Examples

      iex> ttl = Phoenix.SessionProcess.Config.session_ttl()
      iex> is_integer(ttl)
      true
      iex> ttl > 0
      true

  ## Returns

  - `integer()` - Session TTL in milliseconds (default: 3,600,000 = 1 hour)

  ## Configuration

  Set in your config file:

      config :phoenix_session_process,
        session_ttl: :timer.hours(2)  # 2 hours

  ## Note

  Sessions are automatically cleaned up after being idle for this duration.
  """
  @spec session_ttl :: integer()
  def session_ttl do
    get_config(:session_ttl, @default_session_ttl)
  end

  @doc """
  Returns the rate limit for session creation (sessions per minute).

  ## Examples

      iex> limit = Phoenix.SessionProcess.Config.rate_limit()
      iex> is_integer(limit)
      true
      iex> limit > 0
      true

  ## Returns

  - `integer()` - Maximum sessions that can be created per minute (default: 100)

  ## Configuration

  Set in your config file:

      config :phoenix_session_process,
        rate_limit: 200  # Allow 200 sessions per minute

  ## Note

  This helps prevent session creation abuse and protects against DoS attacks.
  """
  @spec rate_limit :: integer()
  def rate_limit do
    get_config(:rate_limit, @default_rate_limit)
  end

  @doc """
  Returns the handler for unmatched actions in reducers.

  ## Examples

      iex> Phoenix.SessionProcess.Config.unmatched_action_handler()
      :log

  ## Returns

  - `:log` - Log debug messages for unmatched actions (default)
  - `:warn` - Log warning messages for unmatched actions
  - `:silent` - No logging
  - `function/3` - Custom handler function with signature: `fun(action, reducer_module, reducer_name)`

  ## Configuration

  Set in your config file:

      config :phoenix_session_process,
        unmatched_action_handler: :warn

      # Or with custom function:
      config :phoenix_session_process,
        unmatched_action_handler: fn action, module, name ->
          MyApp.Metrics.track_unmatched_action(action, module, name)
        end

  ## Note

  This helps debug action routing issues. If you see many unmatched actions,
  consider using `@action_prefix` to limit which actions are routed to each reducer.
  """
  @spec unmatched_action_handler :: :log | :warn | :silent | function()
  def unmatched_action_handler do
    get_config(:unmatched_action_handler, @default_unmatched_action_handler)
  end

  @doc """
  Validates whether a session ID has the correct format.

  ## Examples

      iex> Phoenix.SessionProcess.Config.valid_session_id?("valid_session_123")
      true

      iex> Phoenix.SessionProcess.Config.valid_session_id?("invalid@session")
      false

      iex> Phoenix.SessionProcess.Config.valid_session_id?("")
      false

      iex> Phoenix.SessionProcess.Config.valid_session_id?(nil)
      false

  ## Parameters

  - `session_id` - The session ID to validate

  ## Returns

  - `boolean()` - `true` if the session ID is valid, `false` otherwise

  ## Validation Rules

  - Must be a binary string
  - Length must be between 1 and 64 characters
  - Can only contain alphanumeric characters, underscores, and hyphens
  - This ensures URL-safety and prevents injection attacks
  """
  @spec valid_session_id?(binary()) :: boolean()
  def valid_session_id?(session_id) do
    is_binary(session_id) and
      byte_size(session_id) > 0 and
      byte_size(session_id) <= 64 and
      String.match?(session_id, ~r/^[A-Za-z0-9_-]+$/)
  end

  # Private helper to get config value with proper precedence:
  # 1. Runtime config (ETS table from supervisor start options)
  # 2. Application environment (config files)
  # 3. Default value
  defp get_config(key, default) do
    case lookup_runtime_config(key) do
      {:ok, value} ->
        value

      :not_found ->
        Application.get_env(:phoenix_session_process, key, default)
    end
  end

  # Lookup value from runtime config ETS table
  defp lookup_runtime_config(key) do
    table = :phoenix_session_process_runtime_config

    if :ets.whereis(table) != :undefined do
      case :ets.lookup(table, key) do
        [{^key, value}] -> {:ok, value}
        [] -> :not_found
      end
    else
      :not_found
    end
  end
end
