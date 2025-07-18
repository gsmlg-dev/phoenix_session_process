defmodule Phoenix.SessionProcess.TelemetryTest do
  use ExUnit.Case, async: false

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.{Telemetry, Error}

  test "telemetry events are emitted for session lifecycle" do
    session_id = "telemetry_test_session"

    # Attach telemetry handlers
    events = [
      [:phoenix, :session_process, :start],
      [:phoenix, :session_process, :stop]
    ]

    test_pid = self()

    :ok =
      :telemetry.attach_many(
        "test-handler",
        events,
        fn event, measurements, meta, _ ->
          send(test_pid, {:telemetry_event, event, measurements, meta})
        end,
        nil
      )

    # Test session start telemetry
    assert {:ok, pid} =
             SessionProcess.start(session_id, Phoenix.SessionProcess.DefaultSessionProcess)

    assert_receive {:telemetry_event, [:phoenix, :session_process, :start], measurements, meta}
    assert meta.session_id == session_id
    assert meta.pid == pid
    assert is_integer(measurements.duration)

    # Test session stop telemetry
    assert :ok = SessionProcess.terminate(session_id)
    assert_receive {:telemetry_event, [:phoenix, :session_process, :stop], measurements, meta}
    assert meta.session_id == session_id
    assert meta.pid == pid
    assert is_integer(measurements.duration)

    # Clean up telemetry
    :telemetry.detach("test-handler")
  end

  test "telemetry events for session start errors" do
    session_id = "invalid@session"

    test_pid = self()

    :ok =
      :telemetry.attach(
        "test-start-error-handler",
        [:phoenix, :session_process, :start_error],
        fn event, measurements, meta, _ ->
          send(test_pid, {:telemetry_event, event, measurements, meta})
        end,
        nil
      )

    assert {:error, {:invalid_session_id, ^session_id}} = SessionProcess.start(session_id)

    assert_receive {:telemetry_event, [:phoenix, :session_process, :start_error], measurements,
                    meta},
                   500

    assert meta.session_id == session_id
    assert is_integer(measurements.duration)

    :telemetry.detach("test-start-error-handler")
  end

  test "telemetry measurement helper" do
    test_pid = self()

    :ok =
      :telemetry.attach(
        "test-measure-handler",
        [:phoenix, :session_process, :test_operation],
        fn event, measurements, meta, _ ->
          send(test_pid, {:telemetry_event, event, measurements, meta})
        end,
        nil
      )

    result = Telemetry.measure("test_session", :test_operation, fn -> {:ok, "success"} end)
    assert result == {:ok, "success"}

    assert_receive {:telemetry_event, [:phoenix, :session_process, :test_operation], measurements,
                    meta}

    assert meta.session_id == "test_session"
    assert is_integer(measurements.duration)

    :telemetry.detach("test-measure-handler")
  end

  test "error messages are human-readable" do
    assert Error.message(Error.invalid_session_id("test")) ==
             "Invalid session ID format: \"test\""

    assert Error.message(Error.session_limit_reached(1000)) ==
             "Maximum concurrent sessions limit (1000) reached"

    assert Error.message(Error.session_not_found("test")) ==
             "Session not found: test"

    assert Error.message(Error.timeout(5000)) ==
             "Operation timed out after 5000ms"
  end
end
