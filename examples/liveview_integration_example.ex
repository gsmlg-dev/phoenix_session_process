defmodule Phoenix.SessionProcess.Examples.LiveViewIntegration do
  @moduledoc """
  Complete example of Redux-based LiveView integration with session processes.

  This example demonstrates:
  - Session process using Redux for state management
  - Redux automatically broadcasts state changes via PubSub
  - LiveView that subscribes to Redux state
  - Real-time state synchronization
  - Proper cleanup and error handling
  - Distributed session support (works across nodes)

  ## Running This Example

  This is a reference implementation. To use in your application:

  1. Configure PubSub in your application:

      # config/config.exs
      config :phoenix_session_process,
        pubsub: MyApp.PubSub

  2. Define your session process (like ShoppingCartSession below)
  3. Create your LiveView (like DashboardLive below)
  4. Start the session in your controller or LiveView mount

  ## Architecture

  ```
  ┌─────────────────┐         ┌──────────────────┐
  │  Session        │         │   LiveView       │
  │  Process        │         │   Process        │
  └────────┬────────┘         └────────┬─────────┘
           │                           │
           │  1. mount_session()       │
           │ <─────────────────────────┤
           │                           │
           │  2. :get_redux_state      │
           │ <─────────────────────────┤
           │                           │
           │  3. {:ok, redux}          │
           ├──────────────────────────>│
           │                           │
           │  4. subscribe to Redux    │
           │     PubSub topic          │
           │                           │
  ┌────────┴────────┐         ┌────────┴─────────┐
  │  Phoenix.PubSub │         │  Subscribed!     │
  └────────┬────────┘         └────────┬─────────┘
           │                           │
           │  5. User action           │
           │ <─────────────────────────┤
           │                           │
           │  6. Redux.dispatch()      │
           ├─┐                         │
           │ │                         │
           │<┘                         │
           │                           │
           │  7. Redux broadcasts      │
           │     automatically         │
           │                           │
           │  8. {:redux_state_        │
           │      change, message}     │
           ├──────────────────────────>│
           │                           │
           │                  9. Update UI
           │                           │
  ```
  """

  # ============================================================================
  # Session Process Implementation
  # ============================================================================

  defmodule ShoppingCartSession do
    @moduledoc """
    Example session process using Redux for state management.

    Demonstrates:
    - Redux state initialization with PubSub
    - Dispatching actions via Redux
    - Automatic state broadcasting (no manual calls)
    - Standard GenServer callbacks
    - Helper functions for common operations
    """
    use Phoenix.SessionProcess, :process
    alias Phoenix.SessionProcess.Redux

    @impl true
    def init(_init_arg) do
      # Initialize Redux state with PubSub broadcasting
      redux =
        Redux.init_state(
          %{
            user_id: nil,
            cart_items: [],
            total: 0,
            last_updated: DateTime.utc_now()
          },
          pubsub: MyApp.PubSub,
          pubsub_topic: "session:#{get_session_id()}:redux"
        )

      {:ok, %{redux: redux}}
    end

    # -------------------------------------------------------------------------
    # Synchronous Calls
    # -------------------------------------------------------------------------

    @impl true
    def handle_call(:get_redux_state, _from, state) do
      {:reply, {:ok, state.redux}, state}
    end

    @impl true
    def handle_call({:get_cart_total}, _from, state) do
      current_state = Redux.get_state(state.redux)
      {:reply, {:ok, current_state.total}, state}
    end

    # -------------------------------------------------------------------------
    # Asynchronous Casts (with Redux dispatch)
    # -------------------------------------------------------------------------

    @impl true
    def handle_cast({:set_user, user_id}, state) do
      # Dispatch Redux action - automatically broadcasts to all subscribers
      new_redux = Redux.dispatch(state.redux, {:set_user, user_id}, &reducer/2)
      {:noreply, %{state | redux: new_redux}}
    end

    @impl true
    def handle_cast({:add_item, item}, state) do
      # Dispatch Redux action - broadcasting happens automatically
      new_redux = Redux.dispatch(state.redux, {:add_item, item}, &reducer/2)
      {:noreply, %{state | redux: new_redux}}
    end

    @impl true
    def handle_cast({:remove_item, item_id}, state) do
      new_redux = Redux.dispatch(state.redux, {:remove_item, item_id}, &reducer/2)
      {:noreply, %{state | redux: new_redux}}
    end

    @impl true
    def handle_cast(:clear_cart, state) do
      new_redux = Redux.dispatch(state.redux, :clear_cart, &reducer/2)
      {:noreply, %{state | redux: new_redux}}
    end

    # -------------------------------------------------------------------------
    # Redux Reducer
    # -------------------------------------------------------------------------

    defp reducer(state, action) do
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

    # -------------------------------------------------------------------------
    # Private Helpers
    # -------------------------------------------------------------------------

    defp calculate_total(items) do
      Enum.reduce(items, 0, fn item, acc ->
        acc + item.price * item.quantity
      end)
    end
  end

  # ============================================================================
  # LiveView Implementation
  # ============================================================================

  defmodule DashboardLive do
    @moduledoc """
    Example LiveView that integrates with Redux-based session process.

    Demonstrates:
    - Mounting with Redux session subscription
    - Receiving real-time Redux state updates
    - Sending messages to session
    - Proper cleanup on unmount
    """

    # In a real app, this would be: use MyAppWeb, :live_view
    # use Phoenix.LiveView

    alias Phoenix.SessionProcess.LiveView, as: SessionLV

    # -------------------------------------------------------------------------
    # LiveView Lifecycle
    # -------------------------------------------------------------------------

    def mount(_params, %{"session_id" => session_id}, socket) do
      # Subscribe to Redux session and get initial state
      case SessionLV.mount_session(socket, session_id, MyApp.PubSub) do
        {:ok, socket, state} ->
          # Successfully mounted - store session_id and state
          socket =
            socket
            |> assign(:session_id, session_id)
            |> assign(:cart_state, state)
            |> assign(:loading, false)
            |> assign(:error, nil)

          {:ok, socket}

        {:error, {:session_not_found, _}} ->
          # Session doesn't exist - redirect to login or create new session
          socket =
            socket
            |> assign(:error, "Session not found. Please log in again.")

          # In a real app: |> redirect(to: "/login")

          {:ok, socket}

        {:error, reason} ->
          # Other error - show error message
          socket = assign(socket, :error, "Failed to connect: #{inspect(reason)}")
          {:ok, socket}
      end
    end

    # -------------------------------------------------------------------------
    # Receiving Redux State Updates
    # -------------------------------------------------------------------------

    def handle_info({:redux_state_change, %{state: new_state}}, socket) do
      # Automatically update UI when Redux state changes
      socket = assign(socket, :cart_state, new_state)
      {:noreply, socket}
    end

    # -------------------------------------------------------------------------
    # User Interactions
    # -------------------------------------------------------------------------

    def handle_event("add_to_cart", %{"item" => item_params}, socket) do
      session_id = socket.assigns.session_id

      # Create item from params
      item = %{
        id: System.unique_integer([:positive]),
        name: item_params["name"],
        price: String.to_integer(item_params["price"]),
        quantity: String.to_integer(item_params["quantity"])
      }

      # Send async to session (fire-and-forget)
      # Redux state update will come via {:redux_state_change, ...}
      SessionLV.dispatch_async(session_id, {:add_item, item})

      {:noreply, socket}
    end

    def handle_event("remove_item", %{"item_id" => item_id}, socket) do
      session_id = socket.assigns.session_id
      SessionLV.dispatch_async(session_id, {:remove_item, String.to_integer(item_id)})

      {:noreply, socket}
    end

    def handle_event("clear_cart", _params, socket) do
      session_id = socket.assigns.session_id
      SessionLV.dispatch_async(session_id, :clear_cart)

      {:noreply, socket}
    end

    def handle_event("refresh", _params, socket) do
      # Manually request current Redux state (synchronous)
      session_id = socket.assigns.session_id

      case SessionLV.dispatch(session_id, :get_redux_state) do
        {:ok, redux} ->
          state = redux.current_state
          socket = assign(socket, :cart_state, state)
          {:noreply, socket}

        {:error, reason} ->
          socket = assign(socket, :error, "Failed to refresh: #{inspect(reason)}")
          {:noreply, socket}
      end
    end

    # -------------------------------------------------------------------------
    # Cleanup
    # -------------------------------------------------------------------------

    def terminate(_reason, socket) do
      # Clean up Redux PubSub subscription
      SessionLV.unmount_session(socket)
      :ok
    end

    # -------------------------------------------------------------------------
    # Template (in a real app, this would be in .heex file)
    # -------------------------------------------------------------------------

    # Note: This is pseudo-code showing what the template would look like
    @doc false
    def render_template do
      """
      <div class="dashboard">
        <h1>Shopping Cart (Redux)</h1>

        <%= if @error do %>
          <div class="alert alert-danger"><%= @error %></div>
        <% end %>

        <div class="cart-summary">
          <p>Items: <%= length(@cart_state.cart_items) %></p>
          <p>Total: $<%= @cart_state.total / 100 %></p>
          <p>Last updated: <%= @cart_state.last_updated %></p>
        </div>

        <div class="cart-items">
          <%= for item <- @cart_state.cart_items do %>
            <div class="cart-item">
              <span><%= item.name %></span>
              <span>Qty: <%= item.quantity %></span>
              <span>$<%= item.price / 100 %></span>
              <button phx-click="remove_item" phx-value-item_id="<%= item.id %>">
                Remove
              </button>
            </div>
          <% end %>
        </div>

        <div class="actions">
          <button phx-click="clear_cart">Clear Cart</button>
          <button phx-click="refresh">Refresh</button>
        </div>

        <!-- Add item form -->
        <form phx-submit="add_to_cart">
          <input type="text" name="item[name]" placeholder="Item name" required />
          <input type="number" name="item[price]" placeholder="Price (cents)" required />
          <input type="number" name="item[quantity]" placeholder="Quantity" required />
          <button type="submit">Add to Cart</button>
        </form>
      </div>
      """
    end
  end

  # ============================================================================
  # Controller Integration Example
  # ============================================================================

  defmodule PageController do
    @moduledoc """
    Example controller showing how to start Redux-based session processes.
    """

    # In a real app: use MyAppWeb, :controller

    alias Phoenix.SessionProcess

    def index(conn, _params) do
      session_id = conn.assigns.session_id

      # Start or reuse existing session
      case Phoenix.SessionProcess.start(session_id, ShoppingCartSession) do
        {:ok, _pid} ->
          # Session started successfully
          # render(conn, "index.html")
          :ok

        {:error, {:already_started, _pid}} ->
          # Session already exists - that's fine
          # render(conn, "index.html")
          :ok

        {:error, reason} ->
          # Handle error
          # conn
          # |> put_flash(:error, "Failed to start session: #{inspect(reason)}")
          # |> redirect(to: "/")
          {:error, reason}
      end
    end
  end

  # ============================================================================
  # Advanced: Distributed Sessions
  # ============================================================================

  defmodule DistributedExample do
    @moduledoc """
    Example showing distributed Redux session state across nodes.

    When running multiple nodes, Redux automatically broadcasts
    state changes via PubSub to all subscribed LiveViews on all nodes.
    """

    def start_distributed_session(session_id, node1, node2) do
      # On node1: Start session with Redux
      :rpc.call(node1, Phoenix.SessionProcess, :start, [
        session_id,
        ShoppingCartSession
      ])

      # On node2: LiveView can subscribe and receive Redux updates
      # The Redux PubSub broadcast will work across nodes automatically

      # On node1: Update state via Redux dispatch
      :rpc.call(node1, Phoenix.SessionProcess, :cast, [
        session_id,
        {:add_item, %{id: 1, name: "Widget", price: 1000, quantity: 2}}
      ])

      # On node2: LiveView receives {:redux_state_change, %{state: new_state, ...}}
      # automatically via PubSub
    end
  end

  # ============================================================================
  # Testing Example
  # ============================================================================

  defmodule LiveViewIntegrationTest do
    @moduledoc """
    Example test showing how to test Redux-based LiveView session integration.
    """

    # use ExUnit.Case, async: true
    # use Phoenix.ConnTest
    # import Phoenix.LiveViewTest

    @endpoint MyAppWeb.Endpoint

    # setup do
    #   # Start a test session with Redux
    #   session_id = "test_session_#{System.unique_integer([:positive])}"
    #   {:ok, _pid} = Phoenix.SessionProcess.start(session_id, ShoppingCartSession)
    #
    #   %{session_id: session_id}
    # end

    # test "LiveView receives Redux state updates", %{session_id: session_id} do
    #   # Mount LiveView
    #   {:ok, view, _html} = live(conn, "/dashboard")
    #
    #   # Verify initial state
    #   assert has_element?(view, ".cart-summary", "Items: 0")
    #
    #   # Update session state via Redux dispatch
    #   Phoenix.SessionProcess.cast(session_id, {:add_item, %{
    #     id: 1,
    #     name: "Test Item",
    #     price: 1000,
    #     quantity: 1
    #   }})
    #
    #   # LiveView should update automatically via Redux PubSub
    #   assert has_element?(view, ".cart-summary", "Items: 1")
    #   assert has_element?(view, ".cart-item", "Test Item")
    # end
  end
end
