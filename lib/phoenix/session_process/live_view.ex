defmodule Phoenix.SessionProcess.LiveView do
  @moduledoc """
  LiveView integration helpers for session processes.

  Provides PubSub-based state synchronization between session processes
  and LiveViews, replacing the legacy manual process monitoring approach.

  ## Why PubSub?

  The PubSub-based approach offers several advantages over manual process monitoring:

  - **Decoupling**: LiveViews don't need to directly monitor session processes
  - **Distributed**: Works across nodes in a cluster
  - **Selective Updates**: Only notify LiveViews when relevant state changes
  - **Simpler Cleanup**: Automatic unsubscribe on LiveView termination
  - **Better Performance**: No process links or monitors to manage

  ## Basic Usage

      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView
        alias Phoenix.SessionProcess.LiveView, as: SessionLV

        def mount(_params, %{"session_id" => session_id}, socket) do
          # Get initial state and subscribe to changes
          case SessionLV.mount_session(socket, session_id, MyApp.PubSub) do
            {:ok, socket, initial_state} ->
              {:ok, assign(socket, state: initial_state)}

            {:error, _reason} ->
              {:ok, socket}
          end
        end

        # Handle state changes from session
        def handle_info({:session_state_change, new_state}, socket) do
          {:noreply, assign(socket, state: new_state)}
        end

        def terminate(_reason, socket) do
          SessionLV.unmount_session(socket)
          :ok
        end
      end

  ## Configuration

  Add PubSub module to your application configuration:

      config :phoenix_session_process,
        pubsub: MyApp.PubSub

  ## Session Process Integration

  Your session process should broadcast state changes:

      defmodule MyApp.SessionProcess do
        use Phoenix.SessionProcess, :process

        @impl true
        def init(_init_arg) do
          {:ok, %{user: nil, count: 0}}
        end

        @impl true
        def handle_cast({:increment}, state) do
          new_state = %{state | count: state.count + 1}
          # Broadcast to all subscribers
          broadcast_state_change(new_state)
          {:noreply, new_state}
        end
      end

  ## Custom State Messages

  You can customize which message key retrieves the state:

      {:ok, socket, state} = SessionLV.mount_session(
        socket,
        session_id,
        MyApp.PubSub,
        :get_current_state  # Custom message
      )
  """

  alias Phoenix.SessionProcess

  @doc """
  Mount a LiveView to a session process.

  Gets the current state from the session and subscribes to state changes
  via PubSub. This should be called during LiveView mount.

  ## Parameters
  - `socket` - The LiveView socket
  - `session_id` - The session ID to connect to
  - `pubsub` - The PubSub module (e.g., MyApp.PubSub)
  - `state_key` - Optional message key for state retrieval (default: :get_state)

  ## Returns
  - `{:ok, socket, state}` - Successfully mounted with initial state
  - `{:error, reason}` - Failed to mount (session not found, etc.)

  ## Examples

      def mount(_params, %{"session_id" => session_id}, socket) do
        case SessionLV.mount_session(socket, session_id, MyApp.PubSub) do
          {:ok, socket, state} ->
            {:ok, assign(socket, state: state)}

          {:error, {:session_not_found, _}} ->
            {:ok, redirect(socket, to: "/login")}
        end
      end

      # With custom state message
      {:ok, socket, state} = SessionLV.mount_session(
        socket,
        session_id,
        MyApp.PubSub,
        :get_current_state
      )
  """
  @spec mount_session(term(), String.t(), module(), atom()) ::
          {:ok, term(), any()} | {:error, term()}
  def mount_session(socket, session_id, pubsub, state_key \\ :get_state) do
    # Subscribe to PubSub topic
    topic = "session:#{session_id}:state"
    Phoenix.PubSub.subscribe(pubsub, topic)

    # Get initial state
    case SessionProcess.call(session_id, state_key) do
      {:ok, state} ->
        # Store session info in socket assigns for cleanup
        socket = assign_session_info(socket, session_id, pubsub)
        {:ok, socket, state}

      error ->
        # Unsubscribe on error
        Phoenix.PubSub.unsubscribe(pubsub, topic)
        error
    end
  end

  # Private helper to assign session info to socket
  defp assign_session_info(socket, session_id, pubsub) do
    socket
    |> assign_value(:__session_id__, session_id)
    |> assign_value(:__session_pubsub__, pubsub)
  end

  # Helper that works with both Phoenix.Component.assign/3 and plain map updates
  defp assign_value(socket, key, value) do
    if Code.ensure_loaded?(Phoenix.Component) and
         function_exported?(Phoenix.Component, :assign, 3) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Phoenix.Component, :assign, [socket, key, value])
    else
      # Fallback for when Phoenix.Component is not available
      Map.update!(socket, :assigns, &Map.put(&1, key, value))
    end
  end

  @doc """
  Unmount a LiveView from its session process.

  Unsubscribes from PubSub topic. This should be called in the LiveView's
  terminate callback.

  ## Parameters
  - `socket` - The LiveView socket

  ## Returns
  - `:ok` - Always returns :ok

  ## Examples

      def terminate(_reason, socket) do
        SessionLV.unmount_session(socket)
        :ok
      end
  """
  @spec unmount_session(term()) :: :ok
  def unmount_session(socket) do
    with session_id when not is_nil(session_id) <- socket.assigns[:__session_id__],
         pubsub when not is_nil(pubsub) <- socket.assigns[:__session_pubsub__] do
      topic = "session:#{session_id}:state"
      Phoenix.PubSub.unsubscribe(pubsub, topic)
    end

    :ok
  end

  @doc """
  Dispatch a message to a session process.

  Convenience function for sending messages from LiveView to the session process.

  ## Parameters
  - `session_id` - The session ID
  - `message` - The message to send (handled by handle_call)

  ## Returns
  The result from the session process's handle_call

  ## Examples

      def handle_event("increment", _params, socket) do
        session_id = socket.assigns.session_id
        SessionLV.dispatch(session_id, :increment)
        {:noreply, socket}
      end

      # With parameters
      def handle_event("set_user", %{"id" => id}, socket) do
        result = SessionLV.dispatch(socket.assigns.session_id, {:set_user, id})
        {:noreply, socket}
      end
  """
  @spec dispatch(String.t(), term()) :: any()
  def dispatch(session_id, message) do
    SessionProcess.call(session_id, message)
  end

  @doc """
  Asynchronously dispatch a message to a session process.

  Like `dispatch/2` but uses cast instead of call (fire-and-forget).

  ## Parameters
  - `session_id` - The session ID
  - `message` - The message to send (handled by handle_cast)

  ## Returns
  - `:ok` - Message sent successfully
  - `{:error, reason}` - Failed to send

  ## Examples

      def handle_event("log_activity", _params, socket) do
        SessionLV.dispatch_async(socket.assigns.session_id, :log_activity)
        {:noreply, socket}
      end
  """
  @spec dispatch_async(String.t(), term()) :: :ok | {:error, term()}
  def dispatch_async(session_id, message) do
    SessionProcess.cast(session_id, message)
  end

  @doc """
  Get the PubSub topic for a session.

  Returns the topic string that the session broadcasts to.

  ## Parameters
  - `session_id` - The session ID

  ## Returns
  The PubSub topic string

  ## Examples

      topic = SessionLV.session_topic("user_123")
      # => "session:user_123:state"

      # Subscribe manually
      Phoenix.PubSub.subscribe(MyApp.PubSub, SessionLV.session_topic(session_id))
  """
  @spec session_topic(String.t()) :: String.t()
  def session_topic(session_id) do
    "session:#{session_id}:state"
  end

  @doc """
  Subscribe to a session's state changes without mounting.

  Useful when you want to subscribe to state changes but don't need
  the initial state or full mount/unmount lifecycle.

  ## Parameters
  - `session_id` - The session ID
  - `pubsub` - The PubSub module

  ## Returns
  - `:ok` - Subscribed successfully

  ## Examples

      def mount(_params, %{"session_id" => session_id}, socket) do
        SessionLV.subscribe(session_id, MyApp.PubSub)
        {:ok, socket}
      end

      def handle_info({:session_state_change, state}, socket) do
        {:noreply, assign(socket, remote_state: state)}
      end
  """
  @spec subscribe(String.t(), module()) :: :ok
  def subscribe(session_id, pubsub) do
    Phoenix.PubSub.subscribe(pubsub, session_topic(session_id))
  end

  @doc """
  Unsubscribe from a session's state changes.

  ## Parameters
  - `session_id` - The session ID
  - `pubsub` - The PubSub module

  ## Returns
  - `:ok` - Unsubscribed successfully

  ## Examples

      def handle_event("disconnect", _params, socket) do
        SessionLV.unsubscribe(socket.assigns.session_id, MyApp.PubSub)
        {:noreply, socket}
      end
  """
  @spec unsubscribe(String.t(), module()) :: :ok
  def unsubscribe(session_id, pubsub) do
    Phoenix.PubSub.unsubscribe(pubsub, session_topic(session_id))
  end
end
