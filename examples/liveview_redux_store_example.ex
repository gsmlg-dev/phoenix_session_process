defmodule Phoenix.SessionProcess.Examples.LiveViewReduxStore do
  @moduledoc """
  Complete example of the NEW Redux Store API for LiveView integration.

  This example demonstrates:
  - SessionProcess with built-in Redux Store (NO separate Redux struct)
  - LiveView subscribing directly to SessionProcess
  - Selector-based subscriptions for efficient updates
  - Automatic subscription cleanup via process monitoring
  - 70% less boilerplate compared to old Redux API

  ## Running This Example

  This is a reference implementation. To use in your application:

  1. Define your session process with `user_init/1`:

      defmodule MyApp.SessionProcess do
        use Phoenix.SessionProcess, :process

        def user_init(_args) do
          %{user: nil, cart_items: [], total: 0}
        end
      end

  2. Register reducers for state updates
  3. Subscribe to state changes from LiveView
  4. Dispatch actions to update state

  ## Architecture - New Redux Store API

  ```
  ┌──────────────────────┐
  │  SessionProcess      │
  │  (IS Redux Store)    │
  │                      │
  │  app_state: %{...}   │ ← User's state (from user_init/1)
  │  _redux_reducers     │ ← Registered reducers
  │  _redux_subscriptions│ ← Active subscriptions
  └──────────┬───────────┘
             │
             │ 1. LiveView subscribes with selector
             │    SessionProcess.subscribe(session_id, selector, :event, pid)
             │
             │ 2. SessionProcess monitors LiveView PID
             │    (automatic cleanup when LiveView terminates)
             │
             │ 3. Dispatch action
             │    SessionProcess.dispatch(session_id, action)
             │
             │ 4. SessionProcess runs reducers
             │    new_state = reducer(state, action)
             │
             │ 5. Notify subscriptions with selectors
             │    send(pid, {event_name, selected_value})
             │
             ▼
  ┌──────────────────────┐
  │     LiveView         │
  │                      │
  │  handle_info/2       │ ← Receives {:event_name, value}
  └──────────────────────┘
  ```

  Key differences from old API:
  - NO Redux struct management
  - NO manual PubSub setup
  - Process-level subscriptions (not PubSub)
  - Automatic cleanup via monitoring
  """

  # ============================================================================
  # Session Process Implementation (NEW API)
  # ============================================================================

  defmodule ShoppingCartSession do
    @moduledoc """
    Example session process using the NEW Redux Store API.

    Demonstrates:
    - user_init/1 callback for initial state
    - NO Redux struct - just return state directly
    - SessionProcess handles Redux infrastructure automatically
    """
    use Phoenix.SessionProcess, :process

    # Define initial state - that's it!
    def user_init(_args) do
      %{
        user_id: nil,
        cart_items: [],
        total: 0,
        last_updated: DateTime.utc_now()
      }
    end

    # Optional: You can still override init/1 if needed
    @impl true
    def init(args) do
      # Call super to get Redux infrastructure setup
      super(args)
    end

    # Optional: Define custom reducers as functions
    def cart_reducer(state, action) do
      case action do
        {:set_user, user_id} ->
          %{state | user_id: user_id, last_updated: DateTime.utc_now()}

        {:add_item, item} ->
          new_items = [item | state.cart_items]
          new_total = calculate_total(new_items)

          %{
            state
            | cart_items: new_items,
              total: new_total,
              last_updated: DateTime.utc_now()
          }

        {:remove_item, item_id} ->
          new_items = Enum.reject(state.cart_items, &(&1.id == item_id))
          new_total = calculate_total(new_items)

          %{
            state
            | cart_items: new_items,
              total: new_total,
              last_updated: DateTime.utc_now()
          }

        :clear_cart ->
          %{
            state
            | cart_items: [],
              total: 0,
              last_updated: DateTime.utc_now()
          }

        _ ->
          state
      end
    end

    defp calculate_total(items) do
      Enum.reduce(items, 0, fn item, acc ->
        acc + item.price * item.quantity
      end)
    end
  end

  # ============================================================================
  # LiveView Implementation (NEW API)
  # ============================================================================

  defmodule DashboardLive do
    @moduledoc """
    Example LiveView using the NEW Redux Store API.

    Demonstrates:
    - Direct subscription to SessionProcess (no PubSub)
    - Selector-based subscriptions for efficient updates
    - Automatic cleanup via process monitoring
    - Much simpler code compared to old API
    """

    # In a real app: use MyAppWeb, :live_view
    # use Phoenix.LiveView

    alias Phoenix.SessionProcess
    alias Phoenix.SessionProcess.LiveView, as: SessionLV

    # -------------------------------------------------------------------------
    # LiveView Lifecycle (NEW API)
    # -------------------------------------------------------------------------

    def mount(_params, %{"session_id" => session_id}, socket) do
      # Start session if not already started
      case Phoenix.SessionProcess.start(session_id, ShoppingCartSession) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      # Register reducer
      Phoenix.SessionProcess.register_reducer(
        session_id,
        :cart,
        &ShoppingCartSession.cart_reducer/2
      )

      # NEW API: mount_store with selector
      case SessionLV.mount_store(socket, session_id) do
        {:ok, socket, state} ->
          socket =
            socket
            |> assign(:session_id, session_id)
            |> assign(:cart_state, state)
            |> assign(:loading, false)
            |> assign(:error, nil)

          {:ok, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:error, "Failed to connect: #{inspect(reason)}")

          {:ok, socket}
      end
    end

    # Alternative: Subscribe to specific state slices with selectors
    def mount_with_selectors(_params, %{"session_id" => session_id}, socket) do
      # Subscribe to user only (will only update when user changes)
      {:ok, _sub_id} =
        Phoenix.SessionProcess.subscribe(
          session_id,
          fn state -> state.user_id end,
          :user_changed,
          self()
        )

      # Subscribe to cart items only
      {:ok, _sub_id} =
        Phoenix.SessionProcess.subscribe(
          session_id,
          fn state -> state.cart_items end,
          :cart_items_changed,
          self()
        )

      # Get initial state
      {:ok, state} = Phoenix.SessionProcess.get_state(session_id)

      socket =
        socket
        |> assign(:session_id, session_id)
        |> assign(:cart_state, state)

      {:ok, socket}
    end

    # -------------------------------------------------------------------------
    # Receiving State Updates (NEW API)
    # -------------------------------------------------------------------------

    # Handle full state updates
    def handle_info({:state_changed, new_state}, socket) do
      {:noreply, assign(socket, :cart_state, new_state)}
    end

    # Handle user updates only (from selector subscription)
    def handle_info({:user_changed, user_id}, socket) do
      {:noreply, assign(socket, :user_id, user_id)}
    end

    # Handle cart items updates only (from selector subscription)
    def handle_info({:cart_items_changed, items}, socket) do
      {:noreply, assign(socket, :cart_items, items)}
    end

    # -------------------------------------------------------------------------
    # User Interactions (NEW API)
    # -------------------------------------------------------------------------

    def handle_event("add_to_cart", %{"item" => item_params}, socket) do
      session_id = socket.assigns.session_id

      item = %{
        id: System.unique_integer([:positive]),
        name: item_params["name"],
        price: String.to_integer(item_params["price"]),
        quantity: String.to_integer(item_params["quantity"])
      }

      # NEW API: dispatch to Redux Store (async)
      :ok = SessionLV.dispatch_store(session_id, {:add_item, item}, async: true)

      # State update will come via handle_info({:state_changed, ...})
      {:noreply, socket}
    end

    def handle_event("remove_item", %{"item_id" => item_id}, socket) do
      session_id = socket.assigns.session_id

      # NEW API: dispatch to Redux Store (async)
      :ok =
        SessionLV.dispatch_store(session_id, {:remove_item, String.to_integer(item_id)},
          async: true
        )

      {:noreply, socket}
    end

    def handle_event("clear_cart", _params, socket) do
      session_id = socket.assigns.session_id

      # NEW API: dispatch to Redux Store (sync - get new state immediately)
      {:ok, new_state} = SessionLV.dispatch_store(session_id, :clear_cart)

      # We can update immediately with returned state
      {:noreply, assign(socket, :cart_state, new_state)}
    end

    def handle_event("refresh", _params, socket) do
      session_id = socket.assigns.session_id

      # NEW API: get current state
      case Phoenix.SessionProcess.get_state(session_id) do
        {:ok, state} ->
          {:noreply, assign(socket, :cart_state, state)}

        {:error, reason} ->
          {:noreply, assign(socket, :error, "Failed to refresh: #{inspect(reason)}")}
      end
    end

    # -------------------------------------------------------------------------
    # Cleanup (NEW API)
    # -------------------------------------------------------------------------

    def terminate(_reason, socket) do
      # NEW API: Cleanup is automatic via process monitoring!
      # But you can explicitly unmount if desired:
      SessionLV.unmount_store(socket)
      :ok
    end
  end

  # ============================================================================
  # Comparison: Old API vs New API
  # ============================================================================

  defmodule ComparisonExample do
    @moduledoc """
    Side-by-side comparison of old Redux API vs new Redux Store API.
    """

    @doc """
    OLD API (Deprecated):

    ```elixir
    # Session Process
    defmodule OldSessionProcess do
      use Phoenix.SessionProcess, :process
      alias Phoenix.SessionProcess.Redux

      def init(_args) do
        redux = Redux.init_state(
          %{count: 0},
          pubsub: MyApp.PubSub,
          pubsub_topic: "session:\#{get_session_id()}:redux"
        )
        {:ok, %{redux: redux}}
      end

      def handle_call(:get_redux_state, _from, state) do
        {:reply, {:ok, state.redux}, state}
      end

      def handle_cast({:increment}, state) do
        new_redux = Redux.dispatch(state.redux, :increment, &reducer/2)
        {:noreply, %{state | redux: new_redux}}
      end

      defp reducer(state, :increment), do: %{state | count: state.count + 1}
    end

    # LiveView
    defmodule OldLiveView do
      use Phoenix.LiveView
      alias Phoenix.SessionProcess.LiveView, as: SessionLV

      def mount(_params, %{"session_id" => session_id}, socket) do
        # Mount with PubSub
        case SessionLV.mount_session(socket, session_id, MyApp.PubSub) do
          {:ok, socket, state} ->
            {:ok, assign(socket, state: state)}
        end
      end

      # Handle PubSub messages
      def handle_info({:redux_state_change, %{state: new_state}}, socket) do
        {:noreply, assign(socket, state: new_state)}
      end

      def terminate(_reason, socket) do
        SessionLV.unmount_session(socket)
        :ok
      end
    end
    ```

    NEW API (Recommended):

    ```elixir
    # Session Process
    defmodule NewSessionProcess do
      use Phoenix.SessionProcess, :process

      # That's it! Just return initial state
      def user_init(_args) do
        %{count: 0}
      end
    end

    # LiveView
    defmodule NewLiveView do
      use Phoenix.LiveView
      alias Phoenix.SessionProcess
      alias Phoenix.SessionProcess.LiveView, as: SessionLV

      def mount(_params, %{"session_id" => session_id}, socket) do
        # Register reducer
        Phoenix.SessionProcess.register_reducer(session_id, :counter, fn state, action ->
          case action do
            :increment -> %{state | count: state.count + 1}
            _ -> state
          end
        end)

        # Mount with Redux Store
        case SessionLV.mount_store(socket, session_id) do
          {:ok, socket, state} ->
            {:ok, assign(socket, state: state, session_id: session_id)}
        end
      end

      # Handle state updates
      def handle_info({:state_changed, new_state}, socket) do
        {:noreply, assign(socket, state: new_state)}
      end

      def handle_event("increment", _params, socket) do
        :ok = SessionLV.dispatch_store(socket.assigns.session_id, :increment, async: true)
        {:noreply, socket}
      end

      def terminate(_reason, socket) do
        # Optional - cleanup is automatic!
        SessionLV.unmount_store(socket)
        :ok
      end
    end
    ```

    Benefits of New API:
    - 70% less boilerplate
    - No Redux struct to manage
    - No PubSub configuration needed
    - Automatic subscription cleanup
    - Selector-based subscriptions for efficiency
    - Direct SessionProcess integration
    """
  end
end
