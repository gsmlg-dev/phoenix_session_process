defmodule Phoenix.SessionProcess do
  @moduledoc """
  Documentation for `Phoenix.SessionProcess`.

  Add superviser to process tree

      [
        ...
        {Phoenix.SessionProcess.Supervisor, []}
      ]

  Add this after the `:fetch_session` plug to generate a unique session ID.

      plug :fetch_session
      plug Phoenix.SessionProcess.SessionId

  Start a session process with a session ID.

      Phoenix.SessionProcess.start("session_id")

  This will start a session process using the module defined with

      config :phoenix_session_process, session_process: MySessionProcess

  Or you can start a session process with a specific module.

      Phoenix.SessionProcess.start("session_id", MySessionProcess)
      # or
      Phoenix.SessionProcess.start("session_id", MySessionProcess, arg)

  Check if a session process is started.

      Phoenix.SessionProcess.started?("session_id")

  Terminate a session process.

      Phoenix.SessionProcess.terminate("session_id")

  Genserver call on a session process.

      Phoenix.SessionProcess.call("session_id", request)

  Genserver cast on a session process.

      Phoenix.SessionProcess.cast("session_id", request)

  List all session processes.

      Phoenix.SessionProcess.list_session()
  """

  @spec start(binary()) :: :ignore | {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  defdelegate start(session_id), to: Phoenix.SessionProcess.ProcessSupervisor, as: :start_session
  @spec start(binary(), atom()) :: :ignore | {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  defdelegate start(session_id, module),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :start_session

  @spec start(binary(), atom(), any()) ::
          :ignore | {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  defdelegate start(session_id, module, arg),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :start_session

  @spec started?(binary()) :: boolean()
  defdelegate started?(session_id),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :session_process_started?

  @spec terminate(binary()) :: :ok | {:error, :not_found}
  defdelegate terminate(session_id),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :terminate_session

  @spec call(binary(), any(), :infinity | non_neg_integer()) :: any()
  defdelegate call(session_id, request, timeout \\ 15_000),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :call_on_session

  @spec cast(binary(), any()) :: :ok
  defdelegate cast(session_id, request),
    to: Phoenix.SessionProcess.ProcessSupervisor,
    as: :cast_on_session

  @spec list_session() :: [{binary(), pid()}, ...]
  def list_session() do
    Registry.select(Phoenix.SessionProcess.Registry, [
      {{:":$1", :":$2", :_}, [], [{{:":$1", :":$2"}}]}
    ])
  end

  defmacro __using__(:process) do
    quote do
      use GenServer

      def start_link(opts) do
        arg = Keyword.get(opts, :arg, %{})
        name = Keyword.get(opts, :name)
        GenServer.start_link(__MODULE__, arg, name: name)
      end

      def get_session_id() do
        current_pid = self()

        Registry.select(Phoenix.SessionProcess.Registry, [
          {{:":$1", :":$2", :_}, [{:==, :":$2", current_pid}], [{{:":$1", :":$2"}}]}
        ])
        |> Enum.at(0)
        |> elem(0)
      end
    end
  end

  defmacro __using__(:process_link) do
    quote do
      use GenServer

      def start_link(opts) do
        args = Keyword.get(opts, :args, %{})
        name = Keyword.get(opts, :name)
        GenServer.start_link(__MODULE__, args, name: name)
      end

      def get_session_id() do
        current_pid = self()

        Registry.select(Phoenix.SessionProcess.Registry, [
          {{:":$1", :":$2", :_}, [{:==, :":$2", current_pid}], [{{:":$1", :":$2"}}]}
        ])
        |> Enum.at(0)
        |> elem(0)
      end

      def handle_cast({:monitor, pid}, state) do
        new_state =
          state |> Map.update(:__live_view__, [pid], fn views -> [pid | views] end)

        Process.monitor(pid)
        {:noreply, new_state}
      end

      def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
        new_state =
          state
          |> Map.update(:__live_view__, [], fn views -> views |> Enum.filter(&(&1 != pid)) end)

        {:noreply, new_state}
      end

      def terminate(_reason, state) do
        state
        |> Map.get(:__live_view__, [])
        |> Enum.each(&Process.send_after(&1, :session_expired, 0))
      end
    end
  end
end
