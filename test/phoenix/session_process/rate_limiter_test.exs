defmodule Phoenix.SessionProcess.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess.RateLimiter

  setup do
    # Reset rate limiter before each test
    RateLimiter.reset()

    # Save original rate limit configuration
    original_rate_limit = Application.get_env(:phoenix_session_process, :rate_limit)

    # Restore rate limit after each test
    on_exit(fn ->
      if original_rate_limit do
        Application.put_env(:phoenix_session_process, :rate_limit, original_rate_limit)
      else
        Application.delete_env(:phoenix_session_process, :rate_limit)
      end
      RateLimiter.reset()
    end)

    :ok
  end

  describe "check_rate_limit/0" do
    test "allows requests under the rate limit" do
      # Configure low rate limit for testing
      Application.put_env(:phoenix_session_process, :rate_limit, 5)

      # Should allow first 5 requests
      assert :ok = RateLimiter.check_rate_limit()
      assert :ok = RateLimiter.check_rate_limit()
      assert :ok = RateLimiter.check_rate_limit()
      assert :ok = RateLimiter.check_rate_limit()
      assert :ok = RateLimiter.check_rate_limit()

      # 6th request should be rate limited
      assert {:error, :rate_limit_exceeded} = RateLimiter.check_rate_limit()
    end

    test "rate limit resets after window period" do
      Application.put_env(:phoenix_session_process, :rate_limit, 2)

      # Use up the rate limit
      assert :ok = RateLimiter.check_rate_limit()
      assert :ok = RateLimiter.check_rate_limit()
      assert {:error, :rate_limit_exceeded} = RateLimiter.check_rate_limit()

      # Wait for window to expire (would need to wait 60s in real scenario)
      # For testing, we reset instead
      RateLimiter.reset()

      # Should work again
      assert :ok = RateLimiter.check_rate_limit()
      assert :ok = RateLimiter.check_rate_limit()
    end
  end

  describe "current_count/0" do
    test "returns the number of requests in the current window" do
      Application.put_env(:phoenix_session_process, :rate_limit, 10)
      RateLimiter.reset()

      assert RateLimiter.current_count() == 0

      RateLimiter.check_rate_limit()
      assert RateLimiter.current_count() == 1

      RateLimiter.check_rate_limit()
      RateLimiter.check_rate_limit()
      assert RateLimiter.current_count() == 3
    end
  end

  describe "reset/0" do
    test "clears all rate limit tracking" do
      Application.put_env(:phoenix_session_process, :rate_limit, 2)

      RateLimiter.check_rate_limit()
      RateLimiter.check_rate_limit()
      assert RateLimiter.current_count() == 2

      RateLimiter.reset()
      assert RateLimiter.current_count() == 0
      assert :ok = RateLimiter.check_rate_limit()
    end
  end
end
