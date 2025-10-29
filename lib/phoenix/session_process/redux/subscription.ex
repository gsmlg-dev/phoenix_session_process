defmodule Phoenix.SessionProcess.Redux.Subscription do
  @moduledoc """
  Subscription management for Redux state changes.

  Allows subscribing to Redux state changes with optional selectors for
  fine-grained notifications. Only notifies when selected values change.

  ## Basic Usage

      # Subscribe to all state changes
      redux = Redux.subscribe(redux, fn state ->
        IO.inspect(state, label: "State changed")
      end)

      # Or with subscription ID for later unsubscribe
      {redux, sub_id} = Subscription.subscribe_to_struct(redux, nil, fn state ->
        IO.inspect(state, label: "State changed")
      end)

      # Unsubscribe
      redux = Redux.unsubscribe(redux, sub_id)

  ## With Selectors (Recommended)

      # Only notify when user changes
      user_selector = fn state -> state.user end

      redux = Redux.subscribe(redux, user_selector, fn user ->
        IO.inspect(user, label: "User changed")
      end)

  ## Advanced Example

      # Subscribe with composed selector
      alias Phoenix.SessionProcess.Redux.Selector

      filtered_items = Selector.create_selector(
        [
          fn state -> state.items end,
          fn state -> state.filter end
        ],
        fn items, filter ->
          Enum.filter(items, &(&1.type == filter))
        end
      )

      redux = Redux.subscribe(redux, filtered_items, fn items ->
        # Only called when filtered items actually change
        update_ui(items)
      end)

  ## Use Cases

  - **LiveView Integration**: Update assigns when relevant state changes
  - **Phoenix Channels**: Broadcast updates to connected clients
  - **Audit Trail**: Log state changes for debugging
  - **Side Effects**: Trigger actions based on state changes

  ## Performance

  Subscriptions with selectors use shallow equality checks to determine
  if the selected value has changed. This prevents unnecessary callbacks
  when unrelated state changes.
  """

  alias Phoenix.SessionProcess.Redux
  alias Phoenix.SessionProcess.Redux.Selector

  @type subscription_id :: reference()
  @type selector :: Selector.selector()
  @type callback :: (any() -> any())

  @type subscription :: %{
          id: subscription_id(),
          selector: selector() | nil,
          callback: callback(),
          last_value: any()
        }

  @doc """
  Subscribe to state changes on a Redux struct.

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
    current_value =
      if selector do
        Selector.select(redux, selector)
      else
        Redux.get_state(redux)
      end

    # Create subscription
    subscription = %{
      id: make_ref(),
      selector: selector,
      callback: callback,
      last_value: current_value
    }

    # Invoke callback immediately with current value
    invoke_callback(callback, current_value)

    # Add subscription to Redux
    new_redux = %{redux | subscriptions: [subscription | redux.subscriptions]}

    {new_redux, subscription.id}
  end

  @doc """
  Unsubscribe from state changes.

  ## Examples

      {redux, id} = Subscription.subscribe_to_struct(redux, nil, callback)
      redux = Subscription.unsubscribe_from_struct(redux, id)

  """
  @spec unsubscribe_from_struct(Redux.t(), subscription_id()) :: Redux.t()
  def unsubscribe_from_struct(redux, subscription_id) do
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

  defp notify_subscription(%{selector: nil, callback: callback} = sub, new_state) do
    # No selector, always notify
    invoke_callback(callback, new_state)
    %{sub | last_value: new_state}
  end

  defp notify_subscription(
         %{selector: selector, callback: callback, last_value: last_value} = sub,
         new_state
       ) do
    # Extract new value using selector
    # Wrap in try/catch to handle selector errors
    # credo:disable-for-next-line Credo.Check.Readability.PreferImplicitTry
    try do
      new_value = apply_selector(selector, new_state)

      # Check if value changed (shallow equality)
      if new_value != last_value do
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
