defmodule Phoenix.SessionProcess.ProcessBehaviour do
  @moduledoc """
  Defines the behaviour for session processes in Phoenix.SessionProcess.

  Session processes are GenServer processes that manage isolated state for each user session.
  They integrate with the Redux Store infrastructure for state management.

  ## Required Callbacks

  - `init_state/1` - Initialize the session's application state (required)

  ## Optional Callbacks

  - `combined_reducers/0` - Define reducer modules for state slicing (optional)
  - GenServer callbacks (`handle_call/3`, `handle_cast/2`, etc.) - Handle custom messages (optional)

  ## Usage

  To create a session process, use the `:process` macro:

      defmodule MyApp.SessionProcess do
        use Phoenix.SessionProcess, :process

        @impl true
        def init_state(_arg) do
          %{user_id: nil, cart: [], preferences: %{}}
        end

        # Optional: Define reducers for state slicing
        @impl true
        def combined_reducers do
          [
            MyApp.CounterReducer,
            MyApp.UserReducer
          ]
        end

        # Optional: Add custom GenServer handlers
        @impl true
        def handle_call(:custom_action, _from, state) do
          {:reply, :ok, state}
        end

        @impl true
        def handle_cast({:custom_event, data}, state) do
          # Custom logic
          {:noreply, state}
        end
      end

  ## Redux Integration

  Session processes automatically include Redux Store infrastructure:

  - **State Management**: All state updates go through `dispatch/4`
  - **Reducers**: Use `combined_reducers/0` to define reducer modules
  - **Subscriptions**: Automatic subscription management with selectors
  - **History**: Optional action history tracking
  - **Async Actions**: Built-in support for async operations

  ## State Structure

  The session process maintains state with two layers:

  1. **Application State** (`state.app_state`):
     - Your custom state from `init_state/1`
     - Reducer slices from `combined_reducers/0`

  2. **Redux Infrastructure** (internal, prefixed with `_redux_`):
     - `_redux_reducers` - Registered reducer modules
     - `_redux_subscriptions` - Active subscriptions
     - `_redux_history` - Action history
     - `_redux_throttle_state` - Throttle/debounce state
     - Other internal state

  ## Example with Reducers

      defmodule MyApp.SessionProcess do
        use Phoenix.SessionProcess, :process

        @impl true
        def init_state(_arg) do
          # Initial state before reducer slices are added
          %{session_created_at: DateTime.utc_now()}
        end

        @impl true
        def combined_reducers do
          [
            MyApp.CounterReducer,    # Adds state.counter slice
            MyApp.UserReducer        # Adds state.user slice
          ]
        end
      end

      # After initialization, state looks like:
      # %{
      #   session_created_at: ~U[2024-01-01 00:00:00Z],
      #   counter: %{count: 0},           # From CounterReducer.init_state/0
      #   user: %{current_user: nil}      # From UserReducer.init_state/0
      # }

  ## Reducer Formats

  The `combined_reducers/0` callback can return three formats:

  1. **Module atom** - Uses the reducer's `@name` and `@action_prefix`:
     ```elixir
     [MyApp.UserReducer]
     ```

  2. **{name, Module} tuple** - Custom name, action_prefix defaults to stringified name:
     ```elixir
     [{:cart, MyApp.CartReducer}]
     ```

  3. **{name, Module, action_prefix} tuple** - Explicit name and action_prefix:
     ```elixir
     [{:shipping, MyApp.ShippingReducer, "ship"}]
     ```

  ## GenServer Integration

  Since `:process` uses `use GenServer`, you can implement any GenServer callback:

  - `handle_call/3` - Synchronous requests
  - `handle_cast/2` - Asynchronous messages
  - `handle_info/2` - Process messages
  - `terminate/2` - Cleanup on shutdown
  - `code_change/3` - Hot code reloading

  ## Accessing Session ID

  Within the session process, use `get_session_id/0` to retrieve the current session ID:

      def handle_call(:get_id, _from, state) do
        session_id = get_session_id()
        {:reply, session_id, state}
      end

  ## Communication

  Use the Phoenix.SessionProcess API to communicate with session processes:

      # Start session
      {:ok, _pid} = Phoenix.SessionProcess.start_session(session_id)

      # Dispatch actions
      :ok = Phoenix.SessionProcess.dispatch(session_id, "counter.increment")
      :ok = Phoenix.SessionProcess.dispatch(session_id, "user.set", %{id: 123})

      # Get state
      state = Phoenix.SessionProcess.get_state(session_id)

      # Custom calls/casts
      {:ok, result} = Phoenix.SessionProcess.call(session_id, :custom_action)
      :ok = Phoenix.SessionProcess.cast(session_id, {:custom_event, data})
  """

  @doc """
  Initialize the session's application state.

  Called during GenServer initialization. Should return a map with your initial
  application state. Reducer slices will be added automatically based on
  `combined_reducers/0`.

  ## Parameters

  - `arg` - Argument passed to `start_session/2` (defaults to `%{}`)

  ## Returns

  - `map()` - Initial application state

  ## Examples

      def init_state(_arg) do
        %{
          user_id: nil,
          cart: [],
          preferences: %{theme: "light"}
        }
      end

      def init_state(user_id) when is_integer(user_id) do
        %{
          user_id: user_id,
          loaded_at: DateTime.utc_now()
        }
      end

      def init_state(%{user_id: user_id, locale: locale}) do
        %{
          user_id: user_id,
          locale: locale,
          cart: []
        }
      end
  """
  @callback init_state(arg :: any()) :: map()

  @doc """
  Define combined reducers for state slicing (optional).

  Return a list of reducer modules or tuples. Each reducer manages its own
  slice of the session state.

  ## Returns

  - `list()` - List of reducer modules or tuples

  ## Formats

  1. **Module atom** - Uses reducer's `@name` and `@action_prefix`:
     ```elixir
     [MyApp.UserReducer]
     ```

  2. **{name, Module} tuple** - Custom name, prefix defaults to stringified name:
     ```elixir
     [{:cart, MyApp.CartReducer}]
     ```

  3. **{name, Module, prefix} tuple** - Custom name and prefix:
     ```elixir
     [{:shipping, MyApp.ShippingReducer, "ship"}]
     ```

  ## Examples

      def combined_reducers do
        [
          MyApp.CounterReducer,
          MyApp.UserReducer,
          {:cart, MyApp.CartReducer},
          {:shipping, MyApp.ShippingReducer, "ship"}
        ]
      end

  ## State Slicing

  Each reducer receives its slice based on the name:

      # Full state
      %{
        counter: %{count: 0},         # CounterReducer (if @name is :counter)
        user: %{current_user: nil},   # UserReducer (if @name is :user)
        cart: %{items: []},           # CartReducer ({:cart, CartReducer})
        shipping: %{address: nil}     # ShippingReducer ({:shipping, ...})
      }
  """
  @callback combined_reducers() :: [
              module()
              | {atom(), module()}
              | {atom(), module(), binary() | nil}
            ]

  @optional_callbacks combined_reducers: 0
end
