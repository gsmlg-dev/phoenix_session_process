defmodule Phoenix.SessionProcess.ReduxExamples do
  @moduledoc """
  Comprehensive examples of Redux state management with Phoenix.SessionProcess.

  This module contains example code demonstrating various Redux patterns and integrations.
  These examples are for documentation purposes and demonstrate best practices.

  ## Table of Contents

  1. Basic Redux Session Process
  2. Redux with LiveView Integration
  3. Redux with Phoenix Channels
  4. Selectors and Memoization
  5. Subscriptions and Reactive State
  6. PubSub for Distributed State
  7. Middleware and Time Travel
  8. Complete Real-World Example

  ## 1. Basic Redux Session Process

  ```elixir
  defmodule MyApp.SessionProcess do
    use Phoenix.SessionProcess, :process
    alias Phoenix.SessionProcess.Redux

    def init(_arg) do
      # Initialize Redux state
      redux = Redux.init_state(%{
        user: nil,
        cart: [],
        notifications: [],
        preferences: %{}
      })

      {:ok, %{redux: redux}}
    end

    # Handle Redux dispatch
    def handle_call({:dispatch, action}, _from, state) do
      new_redux = Redux.dispatch(state.redux, action, &reducer/2)
      {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
    end

    # Handle state queries
    def handle_call(:get_state, _from, state) do
      {:reply, Redux.get_state(state.redux), state}
    end

    # Redux reducer
    defp reducer(state, action) do
      case action do
        {:set_user, user} ->
          %{state | user: user}

        {:add_to_cart, item} ->
          %{state | cart: [item | state.cart]}

        {:remove_from_cart, item_id} ->
          %{state | cart: Enum.reject(state.cart, &(&1.id == item_id))}

        {:add_notification, message} ->
          notification = %{id: generate_id(), message: message, read: false}
          %{state | notifications: [notification | state.notifications]}

        {:mark_notification_read, id} ->
          notifications =
            Enum.map(state.notifications, fn n ->
              if n.id == id, do: %{n | read: true}, else: n
            end)

          %{state | notifications: notifications}

        {:update_preferences, prefs} ->
          %{state | preferences: Map.merge(state.preferences, prefs)}

        :clear_cart ->
          %{state | cart: []}

        _ ->
          state
      end
    end

    defp generate_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
  ```

  ## 2. Redux with LiveView Integration

  ```elixir
  defmodule MyAppWeb.DashboardLive do
    use Phoenix.LiveView
    alias Phoenix.SessionProcess
    alias Phoenix.SessionProcess.Redux.LiveView, as: ReduxLV
    alias Phoenix.SessionProcess.Redux.Selector

    def mount(_params, %{"session_id" => session_id}, socket) do
      if connected?(socket) do
        # Subscribe to specific state changes using selectors
        socket =
          ReduxLV.assign_from_session(socket, session_id, %{
            user: fn state -> state.user end,
            cart_count: Selector.create_selector(
              [fn state -> state.cart end],
              fn cart -> length(cart) end
            ),
            unread_notifications: Selector.create_selector(
              [fn state -> state.notifications end],
              fn notifications ->
                Enum.count(notifications, &(!&1.read))
              end
            )
          })

        {:ok, assign(socket, session_id: session_id)}
      else
        {:ok, assign(socket, session_id: session_id)}
      end
    end

    # Handle automatic assign updates from Redux
    def handle_info({:redux_assign_update, key, value}, socket) do
      {:noreply, ReduxLV.handle_assign_update(socket, key, value)}
    end

    # Handle user interactions
    def handle_event("add_to_cart", %{"item" => item}, socket) do
      ReduxLV.dispatch_to_session(socket.assigns.session_id, {:add_to_cart, item})
      {:noreply, socket}
    end

    def handle_event("mark_notification_read", %{"id" => id}, socket) do
      ReduxLV.dispatch_to_session(
        socket.assigns.session_id,
        {:mark_notification_read, id}
      )

      {:noreply, socket}
    end

    def render(assigns) do
      ~H\"\"\"
      <div>
        <h1>Welcome, <%= @user.name %></h1>
        <div>Cart Items: <%= @cart_count %></div>
        <div>Unread Notifications: <%= @unread_notifications %></div>
      </div>
      \"\"\"
    end
  end
  ```

  ## 3. Redux with Phoenix Channels

  ```elixir
  defmodule MyAppWeb.SessionChannel do
    use Phoenix.Channel
    alias Phoenix.SessionProcess
    alias Phoenix.SessionProcess.Redux
    alias Phoenix.SessionProcess.Redux.Selector

    def join("session:" <> session_id, _params, socket) do
      # Subscribe to Redux state changes
      case SessionProcess.call(session_id, :get_redux_state) do
        {:ok, redux} ->
          # Create selector for cart total
          cart_total_selector =
            Selector.create_selector(
              [fn state -> state.cart end],
              fn cart ->
                Enum.reduce(cart, 0, fn item, acc -> acc + item.price end)
              end
            )

          # Subscribe and broadcast changes to channel
          updated_redux =
            Redux.subscribe(redux, cart_total_selector, fn total ->
              Phoenix.Channel.push(socket, "cart_total_updated", %{total: total})
            end)

          # Update Redux in session
          SessionProcess.cast(session_id, {:update_redux_state, updated_redux})

          {:ok, assign(socket, :session_id, session_id)}

        {:error, reason} ->
          {:error, %{reason: inspect(reason)}}
      end
    end

    def handle_in("dispatch", %{"action" => action}, socket) do
      session_id = socket.assigns.session_id

      case SessionProcess.call(session_id, {:dispatch, action}) do
        {:ok, new_state} ->
          {:reply, {:ok, %{state: new_state}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{reason: inspect(reason)}}, socket}
      end
    end

    def handle_in("get_state", _params, socket) do
      session_id = socket.assigns.session_id

      case SessionProcess.call(session_id, :get_state) do
        state when is_map(state) ->
          {:reply, {:ok, %{state: state}}, socket}

        _ ->
          {:reply, {:error, %{reason: "State not available"}}, socket}
      end
    end
  end
  ```

  ## 4. Selectors and Memoization

  ```elixir
  defmodule MyApp.Selectors do
    alias Phoenix.SessionProcess.Redux.Selector

    # Simple selector
    def user_selector, do: fn state -> state.user end

    # Memoized selector for expensive computation
    def filtered_items_selector do
      Selector.create_selector(
        [
          fn state -> state.items end,
          fn state -> state.filter end
        ],
        fn items, filter ->
          # This only runs when items or filter change
          Enum.filter(items, fn item ->
            String.contains?(String.downcase(item.name), String.downcase(filter))
          end)
        end
      )
    end

    # Composed selectors
    def cart_summary_selector do
      Selector.create_selector(
        [fn state -> state.cart end],
        fn cart ->
          %{
            item_count: length(cart),
            total: Enum.reduce(cart, 0, fn item, acc -> acc + item.price end),
            has_items: length(cart) > 0
          }
        end
      )
    end

    # Multi-level composition
    def dashboard_data_selector do
      Selector.create_selector(
        [
          user_selector(),
          cart_summary_selector(),
          fn state -> state.notifications end
        ],
        fn user, cart_summary, notifications ->
          %{
            user: user,
            cart: cart_summary,
            unread_notifications: Enum.count(notifications, &(!&1.read))
          }
        end
      )
    end
  end
  ```

  ## 5. Subscriptions and Reactive State

  ```elixir
  defmodule MyApp.SessionObserver do
    use GenServer
    alias Phoenix.SessionProcess
    alias Phoenix.SessionProcess.Redux
    alias Phoenix.SessionProcess.Redux.Selector

    def start_link(session_id) do
      GenServer.start_link(__MODULE__, session_id, name: via(session_id))
    end

    def init(session_id) do
      # Subscribe to various state changes
      case SessionProcess.call(session_id, :get_redux_state) do
        {:ok, redux} ->
          # Subscribe to user changes
          {redux, user_sub_id} =
            Redux.Subscription.subscribe_to_struct(
              redux,
              fn state -> state.user end,
              fn user -> send(self(), {:user_changed, user}) end
            )

          # Subscribe to cart changes with selector
          cart_selector =
            Selector.create_selector(
              [fn state -> state.cart end],
              fn cart -> length(cart) end
            )

          {redux, cart_sub_id} =
            Redux.Subscription.subscribe_to_struct(redux, cart_selector, fn count ->
              send(self(), {:cart_count_changed, count})
            end)

          # Update Redux in session
          SessionProcess.cast(session_id, {:update_redux_state, redux})

          {:ok,
           %{
             session_id: session_id,
             user_sub_id: user_sub_id,
             cart_sub_id: cart_sub_id
           }}

        {:error, reason} ->
          {:stop, reason}
      end
    end

    def handle_info({:user_changed, user}, state) do
      # React to user changes
      IO.inspect(user, label: "User changed")
      # Could trigger analytics, logging, etc.
      {:noreply, state}
    end

    def handle_info({:cart_count_changed, count}, state) do
      # React to cart changes
      if count > 10 do
        # Send warning
        SessionProcess.cast(
          state.session_id,
          {:dispatch, {:add_notification, "Cart is getting full!"}}
        )
      end

      {:noreply, state}
    end

    defp via(session_id), do: {:via, Registry, {MyApp.ObserverRegistry, session_id}}
  end
  ```

  ## 6. PubSub for Distributed State

  ```elixir
  defmodule MyApp.DistributedSession do
    use Phoenix.SessionProcess, :process
    alias Phoenix.SessionProcess.Redux

    def init(arg) do
      session_id = Keyword.get(arg, :session_id)

      # Initialize Redux with PubSub
      redux =
        Redux.init_state(
          %{user: nil, data: %{}},
          pubsub: MyApp.PubSub,
          pubsub_topic: "session:\#{session_id}:state"
        )

      {:ok, %{redux: redux, session_id: session_id}}
    end

    def handle_call({:dispatch, action}, _from, state) do
      # Dispatch will automatically broadcast via PubSub
      new_redux = Redux.dispatch(state.redux, action, &reducer/2)
      {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
    end

    defp reducer(state, action) do
      case action do
        {:set_user, user} -> %{state | user: user}
        {:update_data, data} -> %{state | data: Map.merge(state.data, data)}
        _ -> state
      end
    end
  end

  # Observer on another node
  defmodule MyApp.RemoteObserver do
    use GenServer
    alias Phoenix.SessionProcess.Redux

    def start_link(session_id) do
      GenServer.start_link(__MODULE__, session_id)
    end

    def init(session_id) do
      # Subscribe to PubSub broadcasts
      unsubscribe =
        Redux.subscribe_to_broadcasts(
          MyApp.PubSub,
          "session:\#{session_id}:state",
          fn message ->
            send(self(), {:remote_state_change, message})
          end
        )

      {:ok, %{session_id: session_id, unsubscribe: unsubscribe}}
    end

    def handle_info({:remote_state_change, %{action: action, state: state}}, state) do
      IO.inspect(action, label: "Remote action")
      IO.inspect(state, label: "Remote state")
      {:noreply, state}
    end

    def terminate(_reason, state) do
      state.unsubscribe.()
      :ok
    end
  end
  ```

  ## 7. Middleware and Time Travel

  ```elixir
  defmodule MyApp.AdvancedSession do
    use Phoenix.SessionProcess, :process
    alias Phoenix.SessionProcess.Redux

    def init(_arg) do
      # Logger middleware
      logger_middleware = fn action, state, next ->
        IO.puts("[Redux] Dispatching: \#{inspect(action)}")
        new_state = next.(action)
        IO.puts("[Redux] New state: \#{inspect(new_state)}")
        new_state
      end

      # Validation middleware
      validation_middleware = fn action, _state, next ->
        if valid_action?(action) do
          next.(action)
        else
          IO.puts("[Redux] Invalid action: \#{inspect(action)}")
          _state
        end
      end

      redux =
        Redux.init_state(%{count: 0, history: []}, max_history_size: 50)
        |> Redux.add_middleware(logger_middleware)
        |> Redux.add_middleware(validation_middleware)

      {:ok, %{redux: redux}}
    end

    def handle_call({:dispatch, action}, _from, state) do
      new_redux = Redux.dispatch(state.redux, action, &reducer/2)
      {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
    end

    def handle_call({:time_travel, steps}, _from, state) do
      new_redux = Redux.time_travel(state.redux, steps)
      {:reply, {:ok, Redux.get_state(new_redux)}, %{state | redux: new_redux}}
    end

    def handle_call(:get_history, _from, state) do
      {:reply, Redux.history(state.redux), state}
    end

    defp reducer(state, action) do
      case action do
        {:increment, value} -> %{state | count: state.count + value}
        {:decrement, value} -> %{state | count: state.count - value}
        :reset -> %{state | count: 0}
        _ -> state
      end
    end

    defp valid_action?({:increment, value}) when is_integer(value), do: true
    defp valid_action?({:decrement, value}) when is_integer(value), do: true
    defp valid_action?(:reset), do: true
    defp valid_action?(_), do: false
  end
  ```

  ## 8. Complete Real-World Example: E-commerce Session

  See the complete example in the module documentation for a full-featured
  e-commerce session implementation with Redux, selectors, subscriptions,
  LiveView integration, and PubSub broadcasting.
  """
end
