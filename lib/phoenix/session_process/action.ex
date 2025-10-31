defmodule Phoenix.SessionProcess.Action do
  @moduledoc """
  Internal action structure for fast pattern matching.

  Actions are normalized to this struct internally for consistent handling
  and optimized pattern matching in the BEAM VM.

  ## Fields

  - `type` - Action type identifier (must be a binary string)
  - `payload` - Action data (any term)
  - `meta` - Action metadata:
    - `async: true` - Route to handle_async/3 instead of handle_action/2
    - `reducers: [:user, :cart]` - List of reducer names (atoms) to target explicitly.
      * Bypasses normal prefix routing
      * Only specified reducers are called
      * Action type passed WITHOUT prefix stripping
      * Warning logged if reducer doesn't exist
    - `reducer_prefix: "user"` - Only call reducers with this prefix (when `reducers` not specified)
    - Custom metadata for middleware/logging

  ## Usage

  Actions are dispatched using the `dispatch/4` function:

      # Basic action
      dispatch(session_id, "user.reload")

      # With payload
      dispatch(session_id, "user.set", %{id: 123})

      # With meta (async) - note: meta is a keyword list
      dispatch(session_id, "user.fetch", %{page: 1}, async: true)

      # Target specific reducers (bypasses prefix routing, no prefix stripping)
      dispatch(session_id, "user.reload", nil, reducers: [:user, :cart])
      # → Only :user and :cart called, both receive "user.reload" unchanged

  Reducers pattern match on the normalized Action struct for fast, consistent matching.
  """

  @type t :: %__MODULE__{
          type: String.t(),
          payload: term(),
          meta: map()
        }

  @enforce_keys [:type]
  defstruct [:type, payload: nil, meta: %{}]

  @doc """
  Create an Action struct from type, payload, and meta.

  Type must be a binary string. Payload and meta can be any term.

  ## Examples

      iex> Action.new("user.reload", nil, %{})
      %Action{type: "user.reload", payload: nil, meta: %{}}

      iex> Action.new("user.set", %{id: 123}, %{})
      %Action{type: "user.set", payload: %{id: 123}, meta: %{}}

      iex> Action.new("fetch", %{page: 1}, %{async: true})
      %Action{type: "fetch", payload: %{page: 1}, meta: %{async: true}}
  """
  @spec new(String.t(), term(), map()) :: t()
  def new(type, payload \\ nil, meta \\ %{})

  def new(type, payload, meta) when is_binary(type) and is_map(meta) do
    %__MODULE__{
      type: type,
      payload: payload,
      meta: meta
    }
  end

  def new(type, _payload, _meta) when not is_binary(type) do
    raise ArgumentError, """
    Action type must be a binary string, got: #{inspect(type)}

    Examples:
        Action.new("user.reload", nil, %{})  # Correct
        Action.new(:reload, nil, %{})        # Wrong - atom
        Action.new(123, nil, %{})            # Wrong - integer
    """
  end

  def new(_type, _payload, meta) when not is_map(meta) do
    raise ArgumentError, """
    Action meta must be a map, got: #{inspect(meta)}

    Examples:
        Action.new("reload", nil, %{})           # Correct
        Action.new("reload", nil, async: true)   # Wrong - keyword list
    """
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
end
