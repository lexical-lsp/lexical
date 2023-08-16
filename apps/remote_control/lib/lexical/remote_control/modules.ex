defmodule Lexical.RemoteControl.Modules do
  @moduledoc """
  Utilities for dealing with modules on the remote control node
  """
  defmodule Predicate.Syntax do
    @moduledoc """
    Syntax helpers for the predicate syntax
    """
    defmacro __using__(_) do
      quote do
        import unquote(__MODULE__), only: [predicate: 1]
      end
    end

    defmacro predicate(call) do
      predicate_mfa =
        case call do
          {:&, _, [{{:., _, [{:__aliases__, _, module}, fn_name]}, _, args}]} ->
            # This represents the syntax of &Kernel.foo(&1, :a)
            {Module.concat(module), fn_name, capture_to_placeholder(args)}

          {:&, _, [{fn_name, _, args}]} ->
            # This represents foo(:a, :b)
            {Kernel, fn_name, capture_to_placeholder(args)}

          _ ->
            message = """
            Invalid predicate.

              Predicates should look like function captures, i.e.
              predicate(&Module.function(&1, :other)).

              Instead, I got predicate(#{Macro.to_string(call)})
            """

            raise CompileError, description: message, file: __CALLER__.file, line: __CALLER__.line
        end

      Macro.escape(predicate_mfa)
    end

    defp capture_to_placeholder(args) do
      Enum.map(args, fn
        {:&, _, [1]} -> :"$1"
        arg -> arg
      end)
    end
  end

  @cache_timeout Application.compile_env(:remote_control, :modules_cache_expiry, {10, :second})

  @doc """
  Returns all modules matching a prefix

  `with_prefix` returns all modules on the node on which it runs that start with the given prefix.
  It's worth noting that it will return _all modules_ regardless if they have been loaded or not.

  You can optionally pass a predicate function to further select which modules are returned, but
  it's important to understand that the predicate can only be a function reference to a function that
  exists on the `remote_control` node. I.e. you CANNOT pass anonymous functions to this module.

  To ease things, there is a syntax helper in the `Predicate.Syntax` module that allows you to specify
  predicates via a syntax that looks like function captures.
  """
  def with_prefix(prefix_module, predicate_mfa \\ {Function, :identity, [:"$1"]})

  def with_prefix(prefix_module, mfa) when is_atom(prefix_module) do
    prefix_module
    |> to_string()
    |> with_prefix(mfa)
  end

  def with_prefix("Elixir." <> _ = prefix, mfa) do
    results =
      for {module_string, already_loaded?} <- all_modules(),
          String.starts_with?(module_string, prefix),
          module = Module.concat([module_string]),
          ensure_loaded?(module, already_loaded?),
          apply_predicate(module, mfa) do
        {module_string, module}
      end

    {module_strings, modules_with_prefix} = Enum.unzip(results)

    mark_loaded(module_strings)

    modules_with_prefix
  end

  def with_prefix(prefix, mfa) do
    with_prefix("Elixir." <> prefix, mfa)
  end

  defp apply_predicate(module_arg, {invoked_module, function, args}) do
    args =
      Enum.map(args, fn
        :"$1" ->
          module_arg

        other ->
          other
      end)

    apply(invoked_module, function, args)
  end

  defp ensure_loaded?(_, true), do: true
  defp ensure_loaded?(module, _), do: Code.ensure_loaded?(module)

  defp mark_loaded(modules) when is_list(modules) do
    newly_loaded = Map.new(modules, &{&1, true})
    {expires, all_loaded} = :persistent_term.get(__MODULE__)
    updated = Map.merge(all_loaded, newly_loaded)

    :persistent_term.put(__MODULE__, {expires, updated})
  end

  defp all_modules do
    case term() do
      {:ok, modules} ->
        modules

      :error ->
        {_expires, modules} = cache = rebuild_cache()
        :persistent_term.put(__MODULE__, cache)
        modules
    end
  end

  defp term do
    {expires_at, modules} = :persistent_term.get(__MODULE__, {nil, []})

    if expired?(expires_at) do
      :error
    else
      {:ok, modules}
    end
  end

  defp expired?(nil), do: true

  defp expired?(expires) do
    DateTime.compare(DateTime.utc_now(), expires) == :gt
  end

  defp rebuild_cache do
    {amount, unit} = @cache_timeout

    expires = DateTime.add(DateTime.utc_now(), amount, unit)

    module_map =
      Map.new(:code.all_available(), fn {module_charlist, _path, already_loaded?} ->
        {to_string(module_charlist), already_loaded?}
      end)

    {expires, module_map}
  end
end
