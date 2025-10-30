defmodule Phoenix.SessionProcess.Redux.ReducerCompiler do
  @moduledoc """
  Compile-time support for reducer modules.

  This module handles the compilation of `@throttle` and `@debounce` module attributes
  into metadata functions that can be queried at runtime.

  ## Module Attributes

  ### @throttle

  Throttle an action - execute immediately, then block for duration:

      @throttle {"fetch-list", "3000ms"}
      def handle_action(%{type: "fetch-list"}, state) do
        # Only executes once per 3 seconds
      end

  ### @debounce

  Debounce an action - delay execution until duration passes since last call:

      @debounce {"update-query", "500ms"}
      def handle_action(%{type: "update-query", payload: query}, state) do
        # Waits 500ms after last call before executing
      end

  ## Generated Functions

  The compiler generates the following metadata functions:

  - `__reducer_throttles__/0` - Returns list of `{action_pattern, duration}` tuples
  - `__reducer_debounces__/0` - Returns list of `{action_pattern, duration}` tuples
  - `__reducer_module__/0` - Returns `true` to mark as a reducer module
  - `__reducer_action_prefix__/0` - Returns the action prefix for routing (can be nil)
  """

  @doc """
  Called before module compilation completes.

  Generates metadata functions based on accumulated module attributes.
  """
  defmacro __before_compile__(env) do
    throttles = Module.get_attribute(env.module, :action_throttles) || []
    debounces = Module.get_attribute(env.module, :action_debounces) || []
    name = Module.get_attribute(env.module, :name)
    action_prefix = Module.get_attribute(env.module, :action_prefix)

    # Reverse to maintain declaration order
    throttles = Enum.reverse(throttles)
    debounces = Enum.reverse(debounces)

    # Validate name is set
    unless name do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: """
        Reducer module #{inspect(env.module)} must define @name attribute.

        Example:
            defmodule MyReducer do
              use Phoenix.SessionProcess, :reducer

              @name :my_reducer
              @action_prefix "my"  # Optional, defaults to @name, can be nil or "" for no prefix

              def handle_action(%Action{type: "my.action"}, state) do
                # ...
              end
            end
        """
    end

    # Default action_prefix to name (convert atom to string), unless explicitly set
    # action_prefix can be nil or "" to indicate no prefix
    action_prefix =
      cond do
        action_prefix == nil and
            Module.get_attribute(env.module, :action_prefix, :__not_set__) == :__not_set__ ->
          # @action_prefix not set at all, default to stringified name
          to_string(name)

        true ->
          # @action_prefix was explicitly set (could be nil, "", or a string)
          action_prefix
      end

    quote do
      @doc """
      Returns the reducer's name.

      This is used to identify the reducer when routing actions.
      """
      def __reducer_name__, do: unquote(name)

      @doc """
      Returns the reducer's action prefix.

      Actions with type starting with this prefix will be routed to this reducer.
      Can be nil or empty string to indicate no prefix routing.

      ## Examples

          # With @action_prefix "user"
          "user.reload" -> matches
          "user.login" -> matches
          "cart.add" -> no match

          # With @action_prefix nil or ""
          All actions without explicit routing are eligible
      """
      def __reducer_action_prefix__, do: unquote(action_prefix)

      @doc """
      Returns the list of throttle configurations for this reducer.

      Each entry is a tuple: `{action_pattern, duration_string}`

      ## Examples

          iex> MyReducer.__reducer_throttles__()
          [{"fetch-list", "3000ms"}]
      """
      def __reducer_throttles__, do: unquote(Macro.escape(throttles))

      @doc """
      Returns the list of debounce configurations for this reducer.

      Each entry is a tuple: `{action_pattern, duration_string}`

      ## Examples

          iex> MyReducer.__reducer_debounces__()
          [{"update-query", "500ms"}]
      """
      def __reducer_debounces__, do: unquote(Macro.escape(debounces))

      @doc """
      Marks this module as a reducer module.

      Used by the framework to identify reducer modules vs regular modules.
      """
      def __reducer_module__, do: true
    end
  end

  @doc """
  Register a throttle attribute.

  Called automatically when `@throttle` is used in a reducer module.
  Should not be called directly.
  """
  def register_throttle(module, {action_pattern, duration}) when is_binary(duration) do
    Module.put_attribute(module, :action_throttles, {action_pattern, duration})
  end

  @doc """
  Register a debounce attribute.

  Called automatically when `@debounce` is used in a reducer module.
  Should not be called directly.
  """
  def register_debounce(module, {action_pattern, duration}) when is_binary(duration) do
    Module.put_attribute(module, :action_debounces, {action_pattern, duration})
  end
end
