defmodule Phoenix.SessionProcess.Redux.Selector do
  @moduledoc """
  Memoized selectors for efficient state extraction from Redux stores.

  Selectors allow you to extract and compute derived state from Redux stores
  with automatic memoization to prevent unnecessary recomputation.

  ## Basic Usage

      # Simple selector
      user_selector = fn state -> state.user end
      user = Selector.select(redux, user_selector)

      # Composed selector with memoization
      expensive_selector = Selector.create_selector(
        [
          fn state -> state.items end,
          fn state -> state.filter end
        ],
        fn items, filter ->
          # Expensive computation only runs when items or filter change
          Enum.filter(items, fn item -> item.category == filter end)
        end
      )

      result = Selector.select(redux, expensive_selector)

  ## How Memoization Works

  - Simple selectors (functions) are executed on every call
  - Composed selectors (created with `create_selector/2`) cache results
  - Cache key is based on input values from dependency selectors
  - When dependencies return same values, cached result is returned
  - Cache is stored per-process in process dictionary for thread safety

  ## Reselect-style Composition

  Like Redux's reselect library, you can compose selectors:

      user_id_selector = fn state -> state.current_user_id end
      users_selector = fn state -> state.users end

      current_user_selector = Selector.create_selector(
        [user_id_selector, users_selector],
        fn user_id, users -> Map.get(users, user_id) end
      )

  ## Performance Benefits

  - Avoids expensive computations when state hasn't changed
  - Enables shallow equality checks in subscriptions
  - Reduces unnecessary re-renders in LiveView
  - Supports deeply nested state selection

  ## Thread Safety

  Selector caches are stored in the process dictionary, making them
  process-safe. Each process maintains its own cache.
  """

  alias Phoenix.SessionProcess.Redux

  @type selector_fn :: (map() -> any())
  @type composed_selector :: %{
          deps: [selector_fn()],
          compute: ([any()] -> any()),
          cache_key: reference()
        }
  @type selector :: selector_fn() | composed_selector()

  @cache_key :phoenix_session_process_selector_cache

  @doc """
  Execute a selector against a Redux store's current state.

  ## Examples

      # Simple selector
      selector = fn state -> state.count end
      count = Selector.select(redux, selector)

      # Composed selector (memoized)
      composed = Selector.create_selector(
        [fn state -> state.items end],
        fn items -> Enum.count(items) end
      )
      count = Selector.select(redux, composed)

  """
  @spec select(Redux.t(), selector()) :: any()
  def select(redux, %{deps: deps, compute: compute, cache_key: cache_key}) do
    state = Redux.get_state(redux)

    # Extract values from dependency selectors recursively
    dep_values = Enum.map(deps, fn dep ->
      # Handle both simple selectors and composed selectors
      if is_function(dep, 1) do
        dep.(state)
      else
        # Recursively select for composed dependency
        select(redux, dep)
      end
    end)

    # Check cache
    case get_cached_result(cache_key, dep_values) do
      {:hit, result} ->
        result

      :miss ->
        # Compute new result
        result = apply(compute, dep_values)
        # Cache it
        put_cached_result(cache_key, dep_values, result)
        result
    end
  end

  def select(redux, selector) when is_function(selector, 1) do
    state = Redux.get_state(redux)
    selector.(state)
  end

  @doc """
  Create a memoized selector with dependency selectors.

  The compute function receives the results of all dependency selectors
  as separate arguments.

  ## Examples

      # Select filtered items
      selector = Selector.create_selector(
        [
          fn state -> state.items end,
          fn state -> state.filter end
        ],
        fn items, filter ->
          Enum.filter(items, &(&1.type == filter))
        end
      )

      # Compose multiple levels
      base_selector = fn state -> state.data end
      derived_selector = Selector.create_selector(
        [base_selector],
        fn data -> process(data) end
      )
      final_selector = Selector.create_selector(
        [derived_selector],
        fn processed -> aggregate(processed) end
      )

  """
  @spec create_selector([selector_fn()], function()) :: composed_selector()
  def create_selector(deps, compute) when is_list(deps) and is_function(compute) do
    # Validate compute function arity matches dependency count
    arity = length(deps)

    case :erlang.fun_info(compute, :arity) do
      {:arity, ^arity} ->
        %{
          deps: deps,
          compute: compute,
          cache_key: make_ref()
        }

      {:arity, actual_arity} ->
        raise ArgumentError,
              "Compute function arity (#{actual_arity}) does not match " <>
                "number of dependency selectors (#{arity})"
    end
  end

  @doc """
  Clear the selector cache for the current process.

  Useful for testing or when you want to force recomputation.

  ## Examples

      Selector.clear_cache()

  """
  @spec clear_cache() :: :ok
  def clear_cache do
    Process.delete(@cache_key)
    :ok
  end

  @doc """
  Clear the cache for a specific selector.

  ## Examples

      selector = Selector.create_selector([...], fn ... end)
      Selector.clear_selector_cache(selector)

  """
  @spec clear_selector_cache(composed_selector()) :: :ok
  def clear_selector_cache(%{cache_key: cache_key}) do
    cache = get_cache()
    new_cache = Map.delete(cache, cache_key)
    Process.put(@cache_key, new_cache)
    :ok
  end

  def clear_selector_cache(_), do: :ok

  @doc """
  Get cache statistics for monitoring and debugging.

  Returns a map with:
  - `:entries` - Number of cached entries
  - `:selectors` - Number of unique selectors with cache

  ## Examples

      stats = Selector.cache_stats()
      # => %{entries: 5, selectors: 2}

  """
  @spec cache_stats() :: %{entries: non_neg_integer(), selectors: non_neg_integer()}
  def cache_stats do
    cache = get_cache()

    entries =
      cache
      |> Map.values()
      |> Enum.map(&map_size/1)
      |> Enum.sum()

    %{
      entries: entries,
      selectors: map_size(cache)
    }
  end

  # Private functions

  defp get_cache do
    Process.get(@cache_key, %{})
  end

  defp get_cached_result(cache_key, dep_values) do
    cache = get_cache()

    case cache do
      %{^cache_key => selector_cache} ->
        # Create a cache key from dependency values
        value_key = :erlang.phash2(dep_values)

        case selector_cache do
          %{^value_key => result} -> {:hit, result}
          _ -> :miss
        end

      _ ->
        :miss
    end
  end

  defp put_cached_result(cache_key, dep_values, result) do
    cache = get_cache()
    value_key = :erlang.phash2(dep_values)

    selector_cache =
      cache
      |> Map.get(cache_key, %{})
      |> Map.put(value_key, result)

    new_cache = Map.put(cache, cache_key, selector_cache)
    Process.put(@cache_key, new_cache)
    :ok
  end
end
