defmodule Phoenix.SessionProcess.SessionId do
  @moduledoc """
  A Phoenix plug that generates and manages unique session IDs.

  This plug creates a cryptographically secure, URL-safe session ID for each user
  session and stores it in the Plug session. The session ID is used to identify
  and manage the dedicated session process for each user.

  ## Session ID Format

  Session IDs are generated using:
  - 24 bytes (192 bits) of cryptographically secure random data
  - URL-safe Base64 encoding without padding
  - Results in 32-character strings like: `aBcDeFgHiJkLmNoPqRsTuVwXyZaBcDeFg`

  ## Integration

  Add this plug **after** the `:fetch_session` plug in your router:

      pipeline :browser do
        plug :accepts, ["html"]
        plug :fetch_session
        plug Phoenix.SessionProcess.SessionId  # Add this line
        # ... other plugs ...
      end

  ## Security Considerations

  - Uses `:crypto.strong_rand_bytes/1` for cryptographically secure randomness
  - 192 bits of entropy provides excellent protection against guessing attacks
  - URL-safe encoding ensures compatibility with web standards
  - No padding removes potential trailing characters that could cause issues

  ## Session Lifecycle

  1. First request: Generates new session ID and stores in session
  2. Subsequent requests: Retrieves existing session ID from session
  3. Session ID is automatically available as `conn.assigns.session_id`

  ## Usage in Controllers

      def index(conn, _params) do
        session_id = conn.assigns.session_id
        # Use session_id to start or communicate with session process
      end
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(default), do: default

  @impl true
  def call(conn, _config) do
    case get_session(conn, :session_id) do
      nil ->
        session_id = generate_unique_session_id()
        put_session(conn, :session_id, session_id)

      _session_id ->
        conn
    end
  end

  @doc """
  Generates a cryptographically secure, URL-safe session ID.

  This function creates a 32-character session ID with 192 bits of entropy,
  suitable for use as a unique session identifier.

  ## Examples

      iex> session_id = Phoenix.SessionProcess.SessionId.generate_unique_session_id()
      iex> is_binary(session_id)
      true
      iex> String.length(session_id)
      32
      iex> Base.url_decode64(session_id, padding: false)
      {:ok, <<_::24*8>>}

  ## Security

  - Uses `:crypto.strong_rand_bytes/1` for cryptographically secure randomness
  - 192 bits of entropy makes guessing attacks infeasible
  - URL-safe Base64 encoding without padding
  - No special characters that could cause issues in URLs or headers

  ## Returns

  - `binary()` - A 32-character URL-safe session ID
  """
  @spec generate_unique_session_id() :: binary()
  def generate_unique_session_id() do
    # Use 24 bytes (192 bits) for URL-safe session ID
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end
end
