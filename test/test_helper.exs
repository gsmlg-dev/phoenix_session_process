ExUnit.start()

Phoenix.SessionProcess.Supervisor.start_link([])

Application.put_env(:phoenix_session_process, :session_process, TestProcess)
# Set high rate limit for tests to avoid interference
Application.put_env(:phoenix_session_process, :rate_limit, 10_000)
