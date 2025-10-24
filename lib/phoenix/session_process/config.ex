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
    rate_limit: 100                        # Sessions per minute limit
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

  ## Runtime Configuration

  Configuration values are read at runtime, allowing for dynamic updates:

      Application.put_env(:phoenix_session_process, :max_sessions, 20_000)

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
    Application.get_env(:phoenix_session_process, :session_process, @default_session_process)
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
    Application.get_env(:phoenix_session_process, :max_sessions, @default_max_sessions)
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
    Application.get_env(:phoenix_session_process, :session_ttl, @default_session_ttl)
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
    Application.get_env(:phoenix_session_process, :rate_limit, @default_rate_limit)
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
end
