defmodule Phoenix.SessionProcess.Redux.Subscription do
  @moduledoc """
  Subscription management for Redux state changes.

  Allows subscribing to Redux state changes with selector-based notifications.
  Subscribers receive messages when selected values change, with immediate
  delivery of current state on subscribe.

  ## New Message-Based API (Recommended)

      # Subscribe with selector - receives messages instead of callbacks
      {:ok, sub_id, redux} = Subscription.subscribe(
        redux,
        fn state -> state.user end,
        self(),
        :user_changed
      )

      # Immediately receives current user value
      receive do
        {:user_changed, user} -> IO.puts("Current user: \#{inspect(user)}")
      end

      # Receives updates when user changes
      receive do
        {:user_changed, new_user} -> IO.puts("User updated: \#{inspect(new_user)}")
      end

      # Unsubscribe when done
      {:ok, redux} = Subscription.unsubscribe(redux, sub_id)

  ## Key Features

  - **Immediate State Delivery**: Subscribers receive current selected value immediately
  - **Smart Notifications**: Only notified when selected data actually changes
  - **Custom Event Names**: Choose your own event name for messages
  - **Process Monitoring**: Automatic cleanup when subscriber process dies
  - **Shallow Equality**: Efficient change detection using `==` comparison

  ## With Composed Selectors

      alias Phoenix.SessionProcess.Redux.Selector

      # Create memoized selector
      filtered_items = Selector.create_selector(
        [fn state -> state.items end, fn state -> state.filter end],
        fn items, filter -> Enum.filter(items, &(&1.type == filter)) end
      )

      # Subscribe - only notified when filtered result changes
      {:ok, sub_id, redux} = Subscription.subscribe(
        redux,
        filtered_items,
        self(),
        :items_filtered
      )

  ## Process Monitoring

  Subscriptions automatically monitor subscriber processes and clean up
  when they die. Handle `:DOWN` messages in your session process:

      def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
        redux = Subscription.remove_by_monitor(state.redux, ref)
        {:noreply, %{state | redux: redux}}
      end

  ## Legacy Callback API

  The older callback-based API is still supported but deprecated:

      # Legacy - still works
      redux = Redux.subscribe(redux, fn state ->
        IO.inspect(state, label: "State changed")
      end)

  ## Use Cases

  - **LiveView Integration**: Update assigns when relevant state changes
  - **Phoenix Channels**: Broadcast updates to connected clients
  - **Distributed State**: Monitor state across nodes
  - **Reactive UIs**: Auto-update components on state changes

  ## Performance

  - Subscriptions use shallow equality (`==`) for change detection
  - Memoized selectors prevent expensive recomputation
  - Efficient process-based notifications
  """

  alias Phoenix.SessionProcess.Redux
  alias Phoenix.SessionProcess.Redux.Selector

  @type subscription_id :: reference()
  @type selector :: Selector.selector()
  @type callback :: (any() -> any())

  @type subscription :: %{
          id: subscription_id(),
          pid: pid(),
          selector: selector() | nil,
          event_name: atom(),
          last_value: any(),
          monitor_ref: reference(),
          # Legacy support - will be deprecated
          callback: callback() | nil
        }

  @doc """
  Subscribe to state changes on a Redux struct (new API).

  Returns `{:ok, subscription_id, updated_redux}` tuple.

  ## Parameters

  - `redux` - The Redux struct
  - `selector` - Function to extract data from state (required)
  - `pid` - Process to send notifications to (defaults to self())
  - `event_name` - Name of the event message (defaults to :state_updated)

  ## Examples

      # Subscribe with defaults (sends to self() as :state_updated)
      {:ok, id, redux} = Subscription.subscribe(redux, fn state -> state.user end)

      # Subscribe with custom event name
      {:ok, id, redux} = Subscription.subscribe(
        redux,
        fn state -> state.count end,
        self(),
        :count_changed
      )

      # Receive notifications
      receive do
        {:count_changed, count} -> IO.puts("Count: \#{count}")
      end

  """
  @spec subscribe(Redux.t(), selector(), pid(), atom()) ::
          {:ok, subscription_id(), Redux.t()}
  def subscribe(redux, selector, pid \\ self(), event_name \\ :state_updated) do
    # Get current selected value
    current_value = apply_selector_for_subscribe(redux, selector)

    # Monitor the subscriber process
    monitor_ref = Process.monitor(pid)

    # Create subscription
    subscription = %{
      id: make_ref(),
      pid: pid,
      selector: selector,
      event_name: event_name,
      last_value: current_value,
      monitor_ref: monitor_ref,
      # Not used in new API
      callback: nil
    }

    # Send initial value immediately
    send_notification(pid, event_name, current_value)

    # Add subscription to Redux
    new_redux = %{redux | subscriptions: [subscription | redux.subscriptions]}

    {:ok, subscription.id, new_redux}
  end

  @doc """
  Subscribe to state changes on a Redux struct (legacy callback API).

  **DEPRECATED**: Use `subscribe/4` instead for the new message-based API.

  Returns `{redux, subscription_id}` tuple.

  ## Examples

      # Subscribe to all changes
      {redux, id} = Subscription.subscribe_to_struct(redux, nil, fn state ->
        Logger.info("State: \#{inspect(state)}")
      end)

      # Subscribe with selector
      {redux, id} = Subscription.subscribe_to_struct(
        redux,
        fn state -> state.user end,
        fn user -> Logger.info("User: \#{inspect(user)}") end
      )

  """
  @spec subscribe_to_struct(Redux.t(), selector() | nil, callback()) ::
          {Redux.t(), subscription_id()}
  def subscribe_to_struct(redux, selector, callback) when is_function(callback, 1) do
    # Get current selected value
    current_value = apply_selector_for_subscribe(redux, selector)

    # Create subscription (legacy style with callback)
    subscription = %{
      id: make_ref(),
      # Use self() for legacy API
      pid: self(),
      selector: selector,
      # No event name in legacy API
      event_name: nil,
      last_value: current_value,
      # No monitoring in legacy API for backward compat
      monitor_ref: nil,
      callback: callback
    }

    # Invoke callback immediately with current value
    invoke_callback(callback, current_value)

    # Add subscription to Redux
    new_redux = %{redux | subscriptions: [subscription | redux.subscriptions]}

    {new_redux, subscription.id}
  end

  @doc """
  Unsubscribe from state changes by subscription ID.

  Removes the subscription and demonitors the subscriber process.

  ## Examples

      {:ok, id, redux} = Subscription.subscribe(redux, selector)
      {:ok, redux} = Subscription.unsubscribe(redux, id)

  """
  @spec unsubscribe(Redux.t(), subscription_id()) :: {:ok, Redux.t()}
  def unsubscribe(redux, subscription_id) do
    # Find the subscription to demonitor
    subscription = Enum.find(redux.subscriptions, fn sub -> sub.id == subscription_id end)

    # Demonitor if it has a monitor_ref
    if subscription && subscription.monitor_ref do
      Process.demonitor(subscription.monitor_ref, [:flush])
    end

    # Remove the subscription
    new_subscriptions =
      Enum.reject(redux.subscriptions, fn sub -> sub.id == subscription_id end)

    {:ok, %{redux | subscriptions: new_subscriptions}}
  end

  @doc """
  Unsubscribe all subscriptions for a given PID.

  Useful when a process is terminating and wants to clean up all its subscriptions.

  ## Examples

      {:ok, redux} = Subscription.unsubscribe_all(redux, self())

  """
  @spec unsubscribe_all(Redux.t(), pid()) :: {:ok, Redux.t()}
  def unsubscribe_all(redux, pid) do
    # Find all subscriptions for this PID and demonitor them
    redux.subscriptions
    |> Enum.filter(fn sub -> sub.pid == pid end)
    |> Enum.each(fn sub ->
      if sub.monitor_ref do
        Process.demonitor(sub.monitor_ref, [:flush])
      end
    end)

    # Remove all subscriptions for this PID
    new_subscriptions =
      Enum.reject(redux.subscriptions, fn sub -> sub.pid == pid end)

    {:ok, %{redux | subscriptions: new_subscriptions}}
  end

  @doc """
  Remove subscriptions for a dead process by monitor reference.

  This is called automatically when a monitored process dies.

  ## Examples

      redux = Subscription.remove_by_monitor(redux, monitor_ref)

  """
  @spec remove_by_monitor(Redux.t(), reference()) :: Redux.t()
  def remove_by_monitor(redux, monitor_ref) do
    new_subscriptions =
      Enum.reject(redux.subscriptions, fn sub -> sub.monitor_ref == monitor_ref end)

    %{redux | subscriptions: new_subscriptions}
  end

  @doc """
  Unsubscribe from state changes (legacy API).

  ## Examples

      {redux, id} = Subscription.subscribe_to_struct(redux, nil, callback)
      redux = Subscription.unsubscribe_from_struct(redux, id)

  """
  @spec unsubscribe_from_struct(Redux.t(), subscription_id()) :: Redux.t()
  def unsubscribe_from_struct(redux, subscription_id) do
    # Find the subscription to demonitor
    subscription = Enum.find(redux.subscriptions, fn sub -> sub.id == subscription_id end)

    # Demonitor if it has a monitor_ref
    if subscription && subscription.monitor_ref do
      Process.demonitor(subscription.monitor_ref, [:flush])
    end

    # Remove the subscription
    new_subscriptions =
      Enum.reject(redux.subscriptions, fn sub -> sub.id == subscription_id end)

    %{redux | subscriptions: new_subscriptions}
  end

  @doc """
  Notify all subscriptions of a state change.

  This is called automatically by Redux.dispatch/2-3.

  ## Examples

      redux = Subscription.notify_all_struct(redux)

  """
  @spec notify_all_struct(Redux.t()) :: Redux.t()
  def notify_all_struct(redux) do
    new_state = Redux.get_state(redux)

    # Notify each subscription and update last_value if changed
    updated_subscriptions =
      Enum.map(redux.subscriptions, fn sub ->
        notify_subscription(sub, new_state)
      end)

    %{redux | subscriptions: updated_subscriptions}
  end

  @doc """
  Get all active subscriptions from a Redux struct.

  Useful for debugging and monitoring.

  ## Examples

      subscriptions = Subscription.list_subscriptions(redux)
      IO.inspect(length(subscriptions), label: "Active subscriptions")

  """
  @spec list_subscriptions(Redux.t()) :: [subscription()]
  def list_subscriptions(redux) do
    redux.subscriptions
  end

  @doc """
  Clear all subscriptions from a Redux struct.

  Useful for testing or cleanup.

  ## Examples

      redux = Subscription.clear_all_struct(redux)

  """
  @spec clear_all_struct(Redux.t()) :: Redux.t()
  def clear_all_struct(redux) do
    %{redux | subscriptions: []}
  end

  # Private functions

  defp notify_subscription(%{callback: callback} = sub, new_state) when is_function(callback) do
    # Legacy callback-based subscription
    if sub.selector do
      # With selector - only notify if value changed
      # credo:disable-for-next-line Credo.Check.Readability.PreferImplicitTry
      try do
        new_value = apply_selector(sub.selector, new_state)

        if new_value != sub.last_value do
          invoke_callback(callback, new_value)
          %{sub | last_value: new_value}
        else
          sub
        end
      rescue
        error ->
          require Logger

          Logger.error(
            "Selector error in subscription: #{inspect(error)}\n" <>
              Exception.format_stacktrace(__STACKTRACE__)
          )

          sub
      end
    else
      # No selector - always notify
      invoke_callback(callback, new_state)
      %{sub | last_value: new_state}
    end
  end

  defp notify_subscription(
         %{pid: pid, selector: selector, event_name: event_name, last_value: last_value} = sub,
         new_state
       ) do
    # New message-based subscription
    # Extract new value using selector
    # credo:disable-for-next-line Credo.Check.Readability.PreferImplicitTry
    try do
      new_value = apply_selector(selector, new_state)

      # Check if value changed (shallow equality)
      if new_value != last_value do
        send_notification(pid, event_name, new_value)
        %{sub | last_value: new_value}
      else
        sub
      end
    rescue
      error ->
        require Logger

        Logger.error(
          "Selector error in subscription: #{inspect(error)}\n" <>
            Exception.format_stacktrace(__STACKTRACE__)
        )

        # Return subscription unchanged on error
        sub
    end
  end

  defp apply_selector(selector, state) when is_function(selector, 1) do
    selector.(state)
  end

  defp apply_selector(selector, state) when is_map(selector) do
    # For composed selectors, use Selector.select/2
    # We need to wrap state in a minimal Redux struct
    redux = %Phoenix.SessionProcess.Redux{
      current_state: state,
      initial_state: state,
      history: [],
      reducer: nil,
      middleware: [],
      max_history_size: 0,
      pubsub: nil,
      pubsub_topic: nil,
      subscriptions: []
    }

    Selector.select(redux, selector)
  end

  # Apply selector when subscribing - handles both selector and nil
  defp apply_selector_for_subscribe(redux, nil) do
    Redux.get_state(redux)
  end

  defp apply_selector_for_subscribe(redux, selector) do
    Selector.select(redux, selector)
  end

  # Send notification to a process
  defp send_notification(pid, event_name, value) do
    send(pid, {event_name, value})
  end

  defp invoke_callback(callback, value) do
    # credo:disable-for-next-line Credo.Check.Readability.PreferImplicitTry
    try do
      callback.(value)
    rescue
      error ->
        require Logger

        Logger.error(
          "Subscription callback error: #{inspect(error)}\n" <>
            Exception.format_stacktrace(__STACKTRACE__)
        )
    end
  end
end
