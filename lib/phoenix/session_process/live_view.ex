defmodule Phoenix.SessionProcess.LiveView do
  @moduledoc """
  LiveView integration helpers for Redux Store-based session processes.

  Provides two integration patterns:

  ## New Redux Store API (v0.6.0+) - Recommended

  The new API uses SessionProcess's built-in Redux Store for simpler integration:

  - **SessionProcess IS the Redux Store**: No separate Redux struct
  - **Built-in Subscriptions**: Subscribe directly to SessionProcess
  - **Selector-Based Updates**: Only receive notifications when selected state changes
  - **Automatic Cleanup**: Process monitoring handles subscription cleanup
  - **Less Boilerplate**: 70% less code

  Example:
  ```elixir
  def mount(_params, %{"session_id" => session_id}, socket) do
    # Subscribe with selector
    {:ok, _sub_id} = Phoenix.SessionProcess.subscribe(
      session_id,
      fn state -> state.user end,
      :user_changed,
      self()
    )

    {:ok, state} = Phoenix.SessionProcess.get_state(session_id)
    {:ok, assign(socket, state: state, session_id: session_id)}
  end

  def handle_info({:user_changed, user}, socket) do
    {:noreply, assign(socket, user: user)}
  end
  ```

  ## Legacy Redux API (Deprecated)

  The old PubSub-based approach with Redux structs still works but is deprecated:

  - **Manual Redux Struct Management**: Requires managing Redux state in process
  - **PubSub Broadcasting**: Automatic but couples implementation to PubSub
  - **More Boilerplate**: Nested Redux structs and state extraction

  See module documentation below for migration examples.

  ## Basic Usage

      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView
        alias Phoenix.SessionProcess.LiveView, as: SessionLV

        def mount(_params, %{"session_id" => session_id}, socket) do
          # Get initial state and subscribe to Redux changes
          case SessionLV.mount_session(socket, session_id, MyApp.PubSub) do
            {:ok, socket, initial_state} ->
              {:ok, assign(socket, state: initial_state)}

            {:error, _reason} ->
              {:ok, socket}
          end
        end

        # Handle Redux state changes
        def handle_info({:redux_state_change, %{state: new_state}}, socket) do
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

  Your session process must use Redux for state management:

      defmodule MyApp.SessionProcess do
        use Phoenix.SessionProcess, :process
        alias Phoenix.SessionProcess.Redux

        @impl true
        def init(_init_arg) do
          redux = Redux.init_state(
            %{user: nil, count: 0},
            pubsub: MyApp.PubSub,
            pubsub_topic: "session:\#{get_session_id()}:redux"
          )
          {:ok, %{redux: redux}}
        end

        @impl true
        def handle_cast({:increment}, state) do
          new_redux = Redux.dispatch(state.redux, {:increment}, &reducer/2)
          {:noreply, %{state | redux: new_redux}}
        end

        @impl true
        def handle_call(:get_redux_state, _from, state) do
          {:reply, {:ok, state.redux}, state}
        end

        defp reducer(state, action) do
          case action do
            {:increment} -> %{state | count: state.count + 1}
            _ -> state
          end
        end
      end

  ## Custom State Messages

  You can customize which message key retrieves the Redux state:

      {:ok, socket, state} = SessionLV.mount_session(
        socket,
        session_id,
        MyApp.PubSub,
        :get_current_redux_state  # Custom message
      )
  """

  alias Phoenix.SessionProcess

  # ============================================================================
  # New Redux Store API (v0.6.0+)
  # ============================================================================

  @doc """
  Mount a LiveView with the new Redux Store API.

  Subscribes to state changes using SessionProcess's built-in subscription system.
  This is the recommended approach for new code.

  ## Parameters
  - `socket` - The LiveView socket
  - `session_id` - The session ID to connect to
  - `selector` - Optional selector function (default: identity function)
  - `event_name` - Optional event name for notifications (default: :state_changed)

  ## Returns
  - `{:ok, socket, state}` - Successfully mounted with initial state
  - `{:error, reason}` - Failed to mount

  ## Examples

      # Subscribe to full state
      def mount(_params, %{"session_id" => session_id}, socket) do
        case SessionLV.mount_store(socket, session_id) do
          {:ok, socket, state} ->
            {:ok, assign(socket, state: state, session_id: session_id)}

          {:error, _reason} ->
            {:ok, redirect(socket, to: "/login")}
        end
      end

      # Subscribe to specific state slice with selector
      def mount(_params, %{"session_id" => session_id}, socket) do
        user_selector = fn state -> state.user end

        case SessionLV.mount_store(socket, session_id, user_selector, :user_changed) do
          {:ok, socket, user} ->
            {:ok, assign(socket, user: user, session_id: session_id)}

          {:error, _reason} ->
            {:ok, redirect(socket, to: "/login")}
        end
      end

  Then handle updates:

      def handle_info({:state_changed, state}, socket) do
        {:noreply, assign(socket, state: state)}
      end

      def handle_info({:user_changed, user}, socket) do
        {:noreply, assign(socket, user: user)}
      end

  """
  @spec mount_store(term(), String.t(), function(), atom()) ::
          {:ok, term(), any()} | {:error, term()}
  def mount_store(socket, session_id, selector \\ &Function.identity/1, event_name \\ :state_changed) do
    # Subscribe using SessionProcess's built-in subscription
    case SessionProcess.subscribe(session_id, selector, event_name, self()) do
      {:ok, sub_id} ->
        # Get initial state
        case SessionProcess.get_state(session_id, selector) do
          {:ok, initial_value} ->
            # Store subscription info in socket for cleanup
            socket = assign_store_info(socket, session_id, sub_id)
            {:ok, socket, initial_value}

          error ->
            # Clean up subscription on error
            SessionProcess.unsubscribe(session_id, sub_id)
            error
        end

      error ->
        error
    end
  end

  @doc """
  Unmount a LiveView from Redux Store subscriptions.

  Automatically cleans up subscriptions created with `mount_store/4`.
  Note: Subscriptions are also automatically cleaned up via process monitoring,
  so calling this is optional but recommended for explicit cleanup.

  ## Parameters
  - `socket` - The LiveView socket

  ## Returns
  - `:ok` - Always returns :ok

  ## Examples

      def terminate(_reason, socket) do
        SessionLV.unmount_store(socket)
        :ok
      end
  """
  @spec unmount_store(term()) :: :ok
  def unmount_store(socket) do
    with session_id when not is_nil(session_id) <- socket.assigns[:__store_session_id__],
         sub_id when not is_nil(sub_id) <- socket.assigns[:__store_sub_id__] do
      SessionProcess.unsubscribe(session_id, sub_id)
    end

    :ok
  end

  @doc """
  Dispatch an action to the Redux Store.

  Uses the new SessionProcess.dispatch API for state updates.

  ## Parameters
  - `session_id` - The session ID
  - `action` - The action to dispatch
  - `opts` - Options (default: [])
    - `:async` - Whether to dispatch asynchronously (default: false)

  ## Returns
  - `{:ok, new_state}` - Synchronous dispatch returns new state
  - `:ok` - Asynchronous dispatch returns :ok
  - `{:error, reason}` - Dispatch failed

  ## Examples

      # Synchronous dispatch (waits for state update)
      def handle_event("increment", _params, socket) do
        {:ok, new_state} = SessionLV.dispatch_store(
          socket.assigns.session_id,
          :increment
        )
        {:noreply, assign(socket, state: new_state)}
      end

      # Asynchronous dispatch (fire and forget)
      def handle_event("log_activity", _params, socket) do
        :ok = SessionLV.dispatch_store(
          socket.assigns.session_id,
          :log_activity,
          async: true
        )
        {:noreply, socket}
      end
  """
  @spec dispatch_store(String.t(), term(), keyword()) :: {:ok, map()} | :ok | {:error, term()}
  def dispatch_store(session_id, action, opts \\ []) do
    SessionProcess.dispatch(session_id, action, opts)
  end

  # Private helper to assign store subscription info to socket
  defp assign_store_info(socket, session_id, sub_id) do
    socket
    |> assign_value(:__store_session_id__, session_id)
    |> assign_value(:__store_sub_id__, sub_id)
  end

  # ============================================================================
  # Legacy Redux API (Deprecated)
  # ============================================================================

  @doc """
  Mount a LiveView to a Redux-based session process.

  > #### Deprecation Notice {: .warning}
  > This function uses the old Redux struct API and is deprecated as of v0.6.0.
  > Please use `mount_store/4` instead for the new Redux Store API.

  Gets the current Redux state from the session and subscribes to Redux state
  changes via PubSub. This should be called during LiveView mount.

  ## Parameters
  - `socket` - The LiveView socket
  - `session_id` - The session ID to connect to
  - `pubsub` - The PubSub module (e.g., MyApp.PubSub)
  - `state_key` - Optional message key for Redux state retrieval (default: :get_redux_state)

  ## Returns
  - `{:ok, socket, state}` - Successfully mounted with initial Redux state
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

      # With custom Redux state message
      {:ok, socket, state} = SessionLV.mount_session(
        socket,
        session_id,
        MyApp.PubSub,
        :get_current_redux_state
      )
  """
  @deprecated "Use mount_store/4 instead for the new Redux Store API"
  @spec mount_session(term(), String.t(), module(), atom()) ::
          {:ok, term(), any()} | {:error, term()}
  def mount_session(socket, session_id, pubsub, state_key \\ :get_redux_state) do
    # Subscribe to Redux PubSub topic
    topic = "session:#{session_id}:redux"
    Phoenix.PubSub.subscribe(pubsub, topic)

    # Get initial Redux state
    case SessionProcess.call(session_id, state_key) do
      {:ok, redux} ->
        # Extract state from Redux struct
        state = redux.current_state
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
  Unmount a LiveView from its Redux-based session process.

  > #### Deprecation Notice {: .warning}
  > This function uses the old Redux PubSub API and is deprecated as of v0.6.0.
  > Please use `unmount_store/1` instead for the new Redux Store API.

  Unsubscribes from Redux PubSub topic. This should be called in the LiveView's
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
  @deprecated "Use unmount_store/1 instead for the new Redux Store API"
  @spec unmount_session(term()) :: :ok
  def unmount_session(socket) do
    with session_id when not is_nil(session_id) <- socket.assigns[:__session_id__],
         pubsub when not is_nil(pubsub) <- socket.assigns[:__session_pubsub__] do
      topic = "session:#{session_id}:redux"
      Phoenix.PubSub.unsubscribe(pubsub, topic)
    end

    :ok
  end

  @doc """
  Dispatch a message to a session process.

  > #### Deprecation Notice {: .warning}
  > For Redux Store API, use `dispatch_store/3` instead.
  > This function is a simple wrapper around SessionProcess.call and remains available.

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

  > #### Deprecation Notice {: .warning}
  > For Redux Store API, use `dispatch_store/3` with `async: true` instead.
  > This function is a simple wrapper around SessionProcess.cast and remains available.

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
  Get the Redux PubSub topic for a session.

  Returns the Redux topic string that the session broadcasts to.

  ## Parameters
  - `session_id` - The session ID

  ## Returns
  The Redux PubSub topic string

  ## Examples

      topic = SessionLV.session_topic("user_123")
      # => "session:user_123:redux"

      # Subscribe manually
      Phoenix.PubSub.subscribe(MyApp.PubSub, SessionLV.session_topic(session_id))
  """
  @spec session_topic(String.t()) :: String.t()
  def session_topic(session_id) do
    "session:#{session_id}:redux"
  end

  @doc """
  Subscribe to a session's Redux state changes without mounting.

  Useful when you want to subscribe to Redux state changes but don't need
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

      def handle_info({:redux_state_change, %{state: state}}, socket) do
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
