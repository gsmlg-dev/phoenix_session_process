defmodule Phoenix.SessionProcess.Error do
  @moduledoc """
  Comprehensive error handling for Phoenix.SessionProcess operations.

  This module provides structured error types, helper functions for creating errors,
  and utilities for converting errors to human-readable messages. All public functions
  in the Phoenix.SessionProcess library return standardized error tuples that can be
  handled using this module.

  ## Error Types

  The library returns errors in the format `{:error, error_details}` where `error_details`
  follows these patterns:

  ### Session Management Errors
  - `{:invalid_session_id, session_id}` - Session ID format is invalid
  - `{:session_limit_reached, max_sessions}` - Maximum concurrent sessions exceeded
  - `{:session_not_found, session_id}` - Session doesn't exist or has expired

  ### Process Communication Errors
  - `{:process_not_found, session_id}` - Session process not found in registry
  - `{:timeout, timeout}` - Operation timed out
  - `{:call_failed, {module, function, args, reason}}` - GenServer call failed
  - `{:cast_failed, {module, function, args, reason}}` - GenServer cast failed

  ## Usage Examples

  ### Handling Errors

  Use pattern matching to handle different error types returned by Phoenix.SessionProcess functions:

      case Phoenix.SessionProcess.start("session_123") do
        {:ok, _pid} ->
          # Success case

        {:error, {:invalid_session_id, _id}} ->
          # Handle invalid session ID
          {:error, :invalid_session}

        {:error, {:session_limit_reached, _max}} ->
          # Handle session limit exceeded
          {:error, :too_many_sessions}

        {:error, _reason} ->
          # Handle other errors
          {:error, :session_failed}
      end

  ### Creating Custom Errors

  Use the helper functions to create standardized errors:

      Phoenix.SessionProcess.Error.invalid_session_id("invalid@id")
      Phoenix.SessionProcess.Error.session_limit_reached(1000)

  ### Converting to Human-Readable Messages

  Use the `message/1` function to convert errors to human-readable strings:

      error = Phoenix.SessionProcess.Error.invalid_session_id("invalid@id")
      Phoenix.SessionProcess.Error.message(error)
      # Returns: "Invalid session ID format: \"invalid@id\""

  ## Error Recovery Strategies

  ### Session Expiration
  When `{:session_not_found, session_id}` is encountered, it typically means the
  session has expired due to TTL. The appropriate response is to redirect the user
  to login or create a new session.

  ### Rate Limiting
  When `{:session_limit_reached, max_sessions}` occurs, implement backoff strategies
  and consider increasing the `:max_sessions` configuration if appropriate.

  ### Timeout Handling
  Timeout errors may indicate system overload. Consider implementing retry logic
  with exponential backoff for transient failures.
  """

  @typedoc """
  Custom error types returned by Phoenix.SessionProcess functions.
  """
  @type t ::
          {:error,
           {:invalid_session_id, String.t()}
           | {:session_limit_reached, non_neg_integer()}
           | {:session_not_found, String.t()}
           | {:process_not_found, String.t()}
           | {:timeout, timeout()}
           | {:call_failed, {module(), atom(), any(), any()}}
           | {:cast_failed, {module(), atom(), any(), any()}}}

  @doc """
  Creates an invalid session ID error.

  ## Examples

      iex> Phoenix.SessionProcess.Error.invalid_session_id("invalid@id")
      {:error, {:invalid_session_id, "invalid@id"}}
  """
  @spec invalid_session_id(String.t()) :: {:error, {:invalid_session_id, String.t()}}
  def invalid_session_id(session_id) do
    {:error, {:invalid_session_id, session_id}}
  end

  @doc """
  Creates a session limit reached error.
  """
  @spec session_limit_reached(non_neg_integer()) ::
          {:error, {:session_limit_reached, non_neg_integer()}}
  def session_limit_reached(max_sessions) do
    {:error, {:session_limit_reached, max_sessions}}
  end

  @doc """
  Creates a session not found error.
  """
  @spec session_not_found(String.t()) :: {:error, {:session_not_found, String.t()}}
  def session_not_found(session_id) do
    {:error, {:session_not_found, session_id}}
  end

  @doc """
  Creates a process not found error.
  """
  @spec process_not_found(String.t()) :: {:error, {:process_not_found, String.t()}}
  def process_not_found(session_id) do
    {:error, {:process_not_found, session_id}}
  end

  @doc """
  Creates a timeout error.
  """
  @spec timeout(timeout()) :: {:error, {:timeout, timeout()}}
  def timeout(timeout) do
    {:error, {:timeout, timeout}}
  end

  @doc """
  Creates a call failed error.
  """
  @spec call_failed(module(), atom(), any(), any()) :: {:error, {:call_failed, tuple()}}
  def call_failed(module, function, args, reason) do
    {:error, {:call_failed, {module, function, args, reason}}}
  end

  @doc """
  Creates a cast failed error.
  """
  @spec cast_failed(module(), atom(), any(), any()) :: {:error, {:cast_failed, tuple()}}
  def cast_failed(module, function, args, reason) do
    {:error, {:cast_failed, {module, function, args, reason}}}
  end

  @doc """
  Returns a human-readable error message for the given error.
  """
  @spec message(t()) :: String.t()
  def message({:error, {:invalid_session_id, session_id}}) do
    "Invalid session ID format: #{inspect(session_id)}"
  end

  def message({:error, {:session_limit_reached, max_sessions}}) do
    "Maximum concurrent sessions limit (#{max_sessions}) reached"
  end

  def message({:error, {:session_not_found, session_id}}) do
    "Session not found: #{session_id}"
  end

  def message({:error, {:process_not_found, session_id}}) do
    "Process not found for session: #{session_id}"
  end

  def message({:error, {:timeout, timeout}}) do
    "Operation timed out after #{timeout}ms"
  end

  def message({:error, {:call_failed, {module, function, args, reason}}}) do
    "Call failed: #{inspect(module)}.#{function}/#{tuple_size(args) + 1} with reason: #{inspect(reason)}"
  end

  def message({:error, {:cast_failed, {module, function, args, reason}}}) do
    "Cast failed: #{inspect(module)}.#{function}/#{tuple_size(args) + 1} with reason: #{inspect(reason)}"
  end

  @doc """
  Converts a generic error to a SessionProcess error when possible.
  """
  @spec normalize_error(any()) :: {:error, any()}
  def normalize_error({:error, _} = error), do: error
  def normalize_error(:not_found), do: {:error, {:session_not_found, "unknown"}}
  def normalize_error(:timeout), do: {:error, {:timeout, 5000}}
  def normalize_error(error), do: {:error, error}
end
