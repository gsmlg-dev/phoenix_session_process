defmodule Phoenix.SessionProcess.ConfigTest do
  use ExUnit.Case, async: true

  alias Phoenix.SessionProcess.Config

  describe "session_process/0" do
    test "returns default session process when not configured" do
      original_value = Application.get_env(:phoenix_session_process, :session_process)
      Application.delete_env(:phoenix_session_process, :session_process)

      on_exit(fn ->
        if original_value do
          Application.put_env(:phoenix_session_process, :session_process, original_value)
        end
      end)

      assert Config.session_process() == Phoenix.SessionProcess.DefaultSessionProcess
    end

    test "returns configured session process when set" do
      # Temporarily set config
      original_value = Application.get_env(:phoenix_session_process, :session_process)

      on_exit(fn ->
        if original_value do
          Application.put_env(:phoenix_session_process, :session_process, original_value)
        else
          Application.delete_env(:phoenix_session_process, :session_process)
        end
      end)

      Application.put_env(:phoenix_session_process, :session_process, MyCustomSessionProcess)
      assert Config.session_process() == MyCustomSessionProcess
    end
  end

  describe "max_sessions/0" do
    test "returns default max sessions when not configured" do
      assert Config.max_sessions() == 10_000
    end

    test "returns configured max sessions when set" do
      original_value = Application.get_env(:phoenix_session_process, :max_sessions)

      on_exit(fn ->
        if original_value do
          Application.put_env(:phoenix_session_process, :max_sessions, original_value)
        else
          Application.delete_env(:phoenix_session_process, :max_sessions)
        end
      end)

      Application.put_env(:phoenix_session_process, :max_sessions, 5000)
      assert Config.max_sessions() == 5000
    end
  end

  describe "session_ttl/0" do
    test "returns default session TTL when not configured" do
      assert Config.session_ttl() == 3_600_000
    end

    test "returns configured session TTL when set" do
      original_value = Application.get_env(:phoenix_session_process, :session_ttl)

      on_exit(fn ->
        if original_value do
          Application.put_env(:phoenix_session_process, :session_ttl, original_value)
        else
          Application.delete_env(:phoenix_session_process, :session_ttl)
        end
      end)

      Application.put_env(:phoenix_session_process, :session_ttl, 1_800_000)
      assert Config.session_ttl() == 1_800_000
    end
  end

  describe "rate_limit/0" do
    test "returns default rate limit when not configured" do
      # Temporarily remove configuration to test default
      original_value = Application.get_env(:phoenix_session_process, :rate_limit)
      Application.delete_env(:phoenix_session_process, :rate_limit)

      assert Config.rate_limit() == 100

      # Restore original value
      if original_value do
        Application.put_env(:phoenix_session_process, :rate_limit, original_value)
      end
    end

    test "returns configured rate limit when set" do
      original_value = Application.get_env(:phoenix_session_process, :rate_limit)

      on_exit(fn ->
        if original_value do
          Application.put_env(:phoenix_session_process, :rate_limit, original_value)
        else
          Application.delete_env(:phoenix_session_process, :rate_limit)
        end
      end)

      Application.put_env(:phoenix_session_process, :rate_limit, 50)
      assert Config.rate_limit() == 50
    end
  end

  describe "valid_session_id?/1" do
    test "returns true for valid session IDs" do
      valid_ids = [
        "abc123",
        "ABC123",
        "test-session_id",
        "user_session_2023_abc",
        "a1b2c3d4e5f6"
      ]

      for id <- valid_ids do
        assert Config.valid_session_id?(id)
      end
    end

    test "returns false for invalid session IDs" do
      invalid_ids = [
        "",
        "too-long-session-id-" <> String.duplicate("a", 100),
        "invalid@session",
        "invalid session",
        "invalid.session",
        "invalid/session",
        nil,
        123,
        %{}
      ]

      for id <- invalid_ids do
        refute Config.valid_session_id?(id)
      end
    end
  end
end
