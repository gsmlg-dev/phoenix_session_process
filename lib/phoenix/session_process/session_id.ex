defmodule Phoenix.SessionProcess.SessionId do
  @moduledoc """
  Documentation for `Phoenix.SessionProcess.SessionId`.

  Add this after the `:fetch_session` plug to generate a unique session ID.

      plug :fetch_session
      plug Phoenix.SessionProcess.SessionId

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

  @spec generate_unique_session_id() :: binary()
  def generate_unique_session_id() do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end
