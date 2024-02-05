defmodule Phoenix.SessionProcess.SessionIdTest do
  use ExUnit.Case
  doctest Phoenix.SessionProcess

  alias Phoenix.SessionProcess.SessionId

  test "test generate_unique_session_id" do
    session_id = SessionId.generate_unique_session_id()
    assert session_id != :crypto.strong_rand_bytes(16) |> Base.encode16()
    assert String.length(session_id) == 32
  end
end
