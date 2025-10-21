defmodule Phoenix.SessionProcess.SessionIdTest do
  use ExUnit.Case
  # doctest Phoenix.SessionProcess  # Disabled to avoid test interference

  alias Phoenix.SessionProcess.SessionId

  test "test generate_unique_session_id" do
    session_id = SessionId.generate_unique_session_id()
    assert is_binary(session_id)
    assert String.length(session_id) == 32
    assert String.match?(session_id, ~r/^[A-Za-z0-9_-]+$/)
  end
end
