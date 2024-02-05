ExUnit.start()

Phoenix.SessionProcess.Supervisor.start_link([])

Application.put_env(:phoenix_session_process, :session_process, TestProcess)
