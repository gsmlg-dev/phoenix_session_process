defmodule Phoenix.SessionProcess.Redux.LiveView do
  @moduledoc """
  LiveView integration helpers for Redux state management.

  Provides convenient functions to connect Redux state to LiveView assigns
  with automatic updates when state changes.

  ## Basic Usage

      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView
        alias Phoenix.SessionProcess.Redux.LiveView, as: ReduxLV

        def mount(_params, session, socket) do
          session_id = session["session_id"]

          # Subscribe to Redux state changes
          socket = ReduxLV.subscribe_to_session(socket, session_id)

          {:ok, socket}
        end

        # Redux state changes trigger this
        def handle_info({:redux_state_change, state}, socket) do
          {:noreply, assign(socket, :user, state.user)}
        end
      end

  ## With Selectors

      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView
        alias Phoenix.SessionProcess.Redux.LiveView, as: ReduxLV
        alias Phoenix.SessionProcess.Redux.Selector

        def mount(_params, session, socket) do
          session_id = session["session_id"]

          # Only update when user changes
          user_selector = fn state -> state.user end

          socket = ReduxLV.subscribe_to_session(
            socket,
            session_id,
            user_selector,
            fn user -> assign(socket, :user, user) end
          )

          {:ok, socket}
        end
      end

  ## Automatic Assign Updates

      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView
        alias Phoenix.SessionProcess.Redux.LiveView, as: ReduxLV

        def mount(_params, session, socket) do
          session_id = session["session_id"]

          # Automatically map state to assigns
          socket = ReduxLV.assign_from_session(socket, session_id, %{
            user: fn state -> state.user end,
            count: fn state -> state.count end,
            items: fn state -> state.items end
          })

          {:ok, socket}
        end
      end

  ## Distributed LiveView

      # Listen to PubSub broadcasts from any node
      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView
        alias Phoenix.SessionProcess.Redux.LiveView, as: ReduxLV

        def mount(_params, session, socket) do
          session_id = session["session_id"]

          socket = ReduxLV.subscribe_to_pubsub(
            socket,
            MyApp.PubSub,
            "session:\#{session_id}:state"
          )

          {:ok, socket}
        end

        def handle_info({:redux_state_change, message}, socket) do
          # message = %{action: ..., state: ..., timestamp: ...}
          {:noreply, assign(socket, :remote_state, message.state)}
        end
      end
  """

  alias Phoenix.SessionProcess
  alias Phoenix.SessionProcess.Redux
  alias Phoenix.SessionProcess.Redux.Selector

  @doc """
  Subscribe to Redux state changes from a session process.

  Sends `{:redux_state_change, state}` messages to the LiveView process
  on every state change.

  ## Examples

      def mount(_params, %{"session_id" => session_id}, socket) do
        socket = ReduxLV.subscribe_to_session(socket, session_id)
        {:ok, socket}
      end

      def handle_info({:redux_state_change, state}, socket) do
        {:noreply, assign(socket, :state, state)}
      end

  """
  @spec subscribe_to_session(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def subscribe_to_session(socket, session_id) do
    subscribe_to_session(socket, session_id, nil, fn state ->
      send(self(), {:redux_state_change, state})
    end)
  end

  @doc """
  Subscribe to Redux state changes with a selector.

  Only sends messages when the selected value changes.

  ## Examples

      user_selector = fn state -> state.user end

      socket = ReduxLV.subscribe_to_session(socket, session_id, user_selector, fn user ->
        send(self(), {:user_changed, user})
      end)

  """
  @spec subscribe_to_session(
          Phoenix.LiveView.Socket.t(),
          String.t(),
          Selector.selector() | nil,
          function()
        ) :: Phoenix.LiveView.Socket.t()
  def subscribe_to_session(socket, session_id, selector, callback) do
    # Get the Redux state from session process
    case SessionProcess.call(session_id, :get_redux_state) do
      {:ok, redux} ->
        # Subscribe to changes
        updated_redux = Redux.subscribe(redux, selector, callback)

        # Store updated redux back (if using stateful approach)
        # Note: This assumes the session process handles :update_redux_state
        SessionProcess.cast(session_id, {:update_redux_state, updated_redux})

        socket

      {:error, _reason} ->
        # Session not found or doesn't have Redux state
        socket
    end
  end

  @doc """
  Automatically assign values from Redux state to socket assigns.

  Takes a map of assign names to selector functions.

  ## Examples

      socket = ReduxLV.assign_from_session(socket, session_id, %{
        user: fn state -> state.user end,
        count: fn state -> state.count end,
        items: Selector.create_selector(
          [fn s -> s.items end, fn s -> s.filter end],
          fn items, filter -> Enum.filter(items, &(&1.type == filter)) end
        )
      })

  """
  @spec assign_from_session(
          Phoenix.LiveView.Socket.t(),
          String.t(),
          %{atom() => Selector.selector()}
        ) :: Phoenix.LiveView.Socket.t()
  def assign_from_session(socket, session_id, selectors) do
    Enum.reduce(selectors, socket, fn {assign_key, selector}, acc_socket ->
      subscribe_to_session(acc_socket, session_id, selector, fn value ->
        send(self(), {:redux_assign_update, assign_key, value})
      end)
    end)
  end

  @doc """
  Subscribe to PubSub broadcasts for distributed Redux state.

  Useful when you want to listen to state changes from any node.

  ## Examples

      socket = ReduxLV.subscribe_to_pubsub(socket, MyApp.PubSub, "session:123")

      def handle_info({:redux_state_change, message}, socket) do
        # message = %{action: ..., state: ..., timestamp: ...}
        {:noreply, assign(socket, :state, message.state)}
      end

  """
  @spec subscribe_to_pubsub(Phoenix.LiveView.Socket.t(), module(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def subscribe_to_pubsub(socket, pubsub_module, topic) do
    Phoenix.PubSub.subscribe(pubsub_module, topic)
    socket
  end

  @doc """
  Handle Redux assign updates automatically.

  Add this to your LiveView's handle_info to automatically update assigns:

  ## Examples

      def handle_info({:redux_assign_update, key, value}, socket) do
        {:noreply, ReduxLV.handle_assign_update(socket, key, value)}
      end

  """
  @spec handle_assign_update(Phoenix.LiveView.Socket.t(), atom(), any()) ::
          Phoenix.LiveView.Socket.t()
  def handle_assign_update(socket, assign_key, value) do
    Phoenix.Component.assign(socket, assign_key, value)
  end

  @doc """
  Dispatch an action to the Redux store in a session.

  Convenience function for dispatching from LiveView.

  ## Examples

      def handle_event("increment", _params, socket) do
        session_id = socket.assigns.session_id
        ReduxLV.dispatch_to_session(session_id, {:increment, 1})
        {:noreply, socket}
      end

  """
  @spec dispatch_to_session(String.t(), Redux.action()) :: :ok | {:error, term()}
  def dispatch_to_session(session_id, action) do
    case SessionProcess.call(session_id, {:dispatch_redux, action}) do
      {:ok, _redux} -> :ok
      error -> error
    end
  end

  @doc """
  Get the current Redux state from a session.

  ## Examples

      def handle_event("refresh", _params, socket) do
        session_id = socket.assigns.session_id

        case ReduxLV.get_session_state(session_id) do
          {:ok, state} ->
            {:noreply, assign(socket, :state, state)}

          {:error, _} ->
            {:noreply, socket}
        end
      end

  """
  @spec get_session_state(String.t()) :: {:ok, map()} | {:error, term()}
  def get_session_state(session_id) do
    case SessionProcess.call(session_id, :get_redux_state) do
      {:ok, redux} -> {:ok, Redux.get_state(redux)}
      error -> error
    end
  end

  @doc """
  Create a memoized selector for LiveView use.

  This is just an alias for Redux.Selector.create_selector/2 for convenience.

  ## Examples

      expensive_selector = ReduxLV.create_selector(
        [fn state -> state.items end],
        fn items -> Enum.count(items) end
      )

  """
  defdelegate create_selector(deps, compute), to: Selector
end
