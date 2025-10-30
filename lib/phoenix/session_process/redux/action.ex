defmodule Phoenix.SessionProcess.Redux.Action do
  @moduledoc """
  Internal action structure for fast pattern matching.

  Actions are normalized to this struct internally for consistent handling
  and optimized pattern matching in the BEAM VM.

  ## Fields

  - `type` - Action type identifier (string or atom)
  - `payload` - Action data (any term)
  - `meta` - Action metadata:
    - `async: true` - Route to handle_async/3 instead of handle_action/2
    - `reducers: [:user, :cart]` - Only call these named reducers
    - `reducer_prefix: "user"` - Only call reducers with this prefix
    - Custom metadata for middleware/logging

  ## Internal Normalization

  User can dispatch actions in multiple formats, all normalized to Action struct:

      # String -> %Action{type: "user.reload"}
      dispatch(session_id, "user.reload")

      # Atom -> %Action{type: :increment}
      dispatch(session_id, :increment)

      # Tuple -> %Action{type: :set, payload: 100}
      dispatch(session_id, {:set, 100})

      # Map -> %Action{type: "fetch", payload: %{page: 1}}
      dispatch(session_id, %{type: "fetch", payload: %{page: 1}})

      # With meta -> %Action{type: "fetch", meta: %{async: true}}
      dispatch(session_id, "fetch", async: true)

      # Select reducers -> %Action{meta: %{reducers: [:user]}}
      dispatch(session_id, "reload", reducers: [:user, :cart])

  Reducers pattern match on the normalized Action struct for fast, consistent matching.
  """

  @type t :: %__MODULE__{
          type: String.t() | atom(),
          payload: term(),
          meta: map()
        }

  @enforce_keys [:type]
  defstruct [:type, payload: nil, meta: %{}]

  @doc """
  Normalize any action format to internal Action struct.

  ## Examples

      iex> Action.normalize("user.reload")
      %Action{type: "user.reload", payload: nil, meta: %{}}

      iex> Action.normalize(:increment)
      %Action{type: :increment, payload: nil, meta: %{}}

      iex> Action.normalize({:set, 100})
      %Action{type: :set, payload: 100, meta: %{}}

      iex> Action.normalize(%{type: "fetch", payload: %{page: 1}})
      %Action{type: "fetch", payload: %{page: 1}, meta: %{}}

      iex> Action.normalize("fetch", async: true, reducers: [:user])
      %Action{type: "fetch", payload: nil, meta: %{async: true, reducers: [:user]}}

      iex> Action.normalize(%Action{type: "test"})
      %Action{type: "test", payload: nil, meta: %{}}
  """
  @spec normalize(term(), keyword()) :: t()
  def normalize(action, opts \\ [])

  # Already an Action struct - merge meta from opts
  def normalize(%__MODULE__{} = action, opts) when opts == [] do
    action
  end

  def normalize(%__MODULE__{meta: meta} = action, opts) do
    new_meta = Map.merge(meta, Map.new(opts))
    %{action | meta: new_meta}
  end

  # String type - common case
  def normalize(type, opts) when is_binary(type) do
    %__MODULE__{
      type: type,
      payload: Keyword.get(opts, :payload),
      meta: build_meta(opts)
    }
  end

  # Atom type
  def normalize(type, opts) when is_atom(type) do
    %__MODULE__{
      type: type,
      payload: Keyword.get(opts, :payload),
      meta: build_meta(opts)
    }
  end

  # Tuple {type, payload}
  def normalize({type, payload}, opts) do
    %__MODULE__{
      type: type,
      payload: payload,
      meta: build_meta(opts)
    }
  end

  # Map with :type key (atom)
  def normalize(%{type: type} = map, opts) do
    payload = Map.get(map, :payload)
    meta = Map.get(map, :meta, %{})

    %__MODULE__{
      type: type,
      payload: payload,
      meta: Map.merge(meta, build_meta(opts))
    }
  end

  # Map with "type" key (string)
  def normalize(%{"type" => type} = map, opts) do
    payload = Map.get(map, "payload")
    meta = Map.get(map, "meta", %{})

    %__MODULE__{
      type: type,
      payload: payload,
      meta: Map.merge(meta, build_meta(opts))
    }
  end

  # Unknown format - wrap as payload
  def normalize(unknown, opts) do
    %__MODULE__{
      type: :unknown,
      payload: unknown,
      meta: build_meta(opts)
    }
  end

  @doc """
  Check if action should be routed to handle_async/3.

  Returns true if meta contains `async: true`.
  """
  @spec async?(t()) :: boolean()
  def async?(%__MODULE__{meta: %{async: true}}), do: true
  def async?(_), do: false

  @doc """
  Get list of reducer names this action should be routed to.

  Returns nil if action should be routed to all reducers.
  Returns list of reducer names if meta contains `reducers: [...]`.
  """
  @spec target_reducers(t()) :: [atom()] | nil
  def target_reducers(%__MODULE__{meta: %{reducers: reducers}}) when is_list(reducers) do
    reducers
  end

  def target_reducers(_), do: nil

  @doc """
  Get reducer prefix filter if specified.

  Returns nil if no prefix filter.
  Returns string prefix if meta contains `reducer_prefix: "user"`.
  """
  @spec reducer_prefix(t()) :: String.t() | nil
  def reducer_prefix(%__MODULE__{meta: %{reducer_prefix: prefix}}) when is_binary(prefix) do
    prefix
  end

  def reducer_prefix(_), do: nil

  # Private helpers

  defp build_meta(opts) do
    opts
    |> Keyword.drop([:payload])
    |> Map.new()
  end
end
