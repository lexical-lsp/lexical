defmodule Lexical.RemoteControl.CodeIntelligence.Ast.Aliases do
  alias Future.Code, as: Code
  alias Lexical.Document
  alias Lexical.Document.Position
  require Logger

  def at_position(%Document{} = document, %Position{} = position) do
    %{line: line} = position
    # https://github.com/elixir-lang/elixir/issues/12673#issuecomment-1592845875
    position = Position.new(line + 1, 1)

    document
    |> Document.fragment(position)
    |> collect()
  end

  defp collect(fragment) do
    case Code.Fragment.container_cursor_to_quoted(fragment) do
      {:ok, quoted} ->
        {_, mapping} =
          Macro.postwalk(quoted, %{}, fn
            ast, acc -> do_collect(ast, acc, quoted)
          end)

        mapping
        |> maybe_complete_dependent_modules()
        |> Map.merge(cursor_current_module_mapping(quoted))

      _ ->
        %{}
    end
  end

  defp maybe_complete_dependent_modules(mapping) do
    maybe_dependent_modules = dependent_modules(mapping)
    complete_dependent_modules(mapping, maybe_dependent_modules)
  end

  defp dependent_modules(mapping) do
    # NOTE: this is for nested alias
    # for example: alias A.B.C, as: AModule
    #              alias AModule.E.F
    # A.B.C is the be dependented modules
    # AModule is the dependent module
    for {_k, v} <- mapping,
        [head | _] = Module.split(v),
        Map.has_key?(mapping, Module.concat([head])),
        do: head
  end

  defp complete_dependent_modules(mapping, []) do
    mapping
  end

  defp complete_dependent_modules(mapping, dependent_modules) do
    for {k, v} <- mapping, into: %{} do
      [head | tail] = Module.split(v)

      if head in dependent_modules do
        be_dependented = mapping[Module.concat([head])]
        {k, Module.concat([be_dependented | tail])}
      else
        {k, v}
      end
    end
  end

  defp do_collect({:alias, _, [{:__aliases__, _, aliased_module}]} = ast, acc, quoted) do
    # This is for normal alias, like: alias MyModule.MyChild
    to_alias = aliased_module |> List.last() |> List.wrap() |> Module.concat()
    full = full(quoted, aliased_module)
    acc = Map.put(acc, to_alias, full)
    {ast, acc}
  end

  defp do_collect(
         {:alias, _, [{:__aliases__, _, orig_module}, [as: {:__aliases__, _, as_alias}]]} = ast,
         acc,
         quoted
       ) do
    # This is for alias with as, like: alias MyModule.MyChild, as: MyChild
    to_alias = Module.concat(as_alias)
    full = full(quoted, orig_module)
    acc = Map.put(acc, to_alias, full)
    {ast, acc}
  end

  defp do_collect(
         {:alias, _,
          [
            {{:., _, [{:__aliases__, _, parent_modules}, :{}]}, _, children_ast}
          ]} = ast,
         acc,
         _quoted
       ) do
    # This is for unexpanded aliases, like: alias MyModule.{MyChild, MyOther}
    unexpanded = unexpanded_alias_mapping(parent_modules, children_ast)
    {ast, Map.merge(acc, unexpanded)}
  end

  defp do_collect(
         {:alias, _,
          [
            {{:., _, [{:__MODULE__, position, _}, :{}]}, _, children_ast}
          ]} = ast,
         acc,
         quoted
       ) do
    # This is for unexpanded aliases that leading with `__MODULE__`
    # like: alias __MODULE__.{MyChild, MyOtherChild}
    {:ok, parent_modules} = fetch_aliases_of_current_module(quoted, position[:line])
    unexpanded = unexpanded_alias_mapping(parent_modules, children_ast)
    {ast, Map.merge(acc, unexpanded)}
  end

  defp do_collect({:defmodule, _, [{:__aliases__, _, aliases} | _]} = ast, acc, quoted) do
    # This is for implicit aliases, like the `State` module in a GenServer implementation Module
    # or some nested defmodules
    {ast, Map.merge(acc, implicit_alias_mapping(quoted, aliases))}
  end

  defp do_collect(ast, acc, _quoted) do
    {ast, acc}
  end

  defp implicit_alias_mapping(quoted, aliases) do
    path_to_defmodule =
      Macro.path(
        quoted,
        &match?({:defmodule, _, [{:__aliases__, _, ^aliases} | _]}, &1)
      )

    modules =
      path_to_defmodule
      |> Enum.reduce([], fn
        {:defmodule, _, [{:__aliases__, _, aliases} | _]}, acc ->
          acc ++ [Module.concat(aliases)]

        _, acc ->
          acc
      end)

    modules_length = length(modules)

    modules
    |> Enum.with_index(fn module, index ->
      ancestors_to_current_module =
        modules |> Enum.slice(index, modules_length) |> Enum.reverse() |> Module.concat()

      {module, ancestors_to_current_module}
    end)
    |> Map.new()
  end

  defp cursor_current_module_mapping(quoted) do
    path_to_cursor = Macro.path(quoted, &match?({:__cursor__, _, _}, &1))

    modules =
      path_to_cursor
      |> Enum.reduce([], fn
        {:defmodule, _, [{:__aliases__, _, aliases} | _]}, acc ->
          [Module.concat(aliases ++ acc)]

        _, acc ->
          acc
      end)

    if modules != [] do
      [module] = modules
      %{:__MODULE__ => module}
    else
      %{}
    end
  end

  defp unexpanded_alias_mapping(parent_modules, children_ast) do
    for {:__aliases__, _, [child]} <- children_ast, into: %{} do
      {Module.concat([child]), Module.concat(parent_modules ++ [child])}
    end
  end

  defp fetch_aliases_of_current_module(quoted, alias_line) do
    path =
      Macro.path(quoted, fn
        {:defmodule, [line: line], _} when line < alias_line -> true
        _ -> false
      end)

    if path do
      [defs | _] = path
      {:defmodule, _, [{:__aliases__, _, aliases} | _]} = defs
      {:ok, aliases}
    else
      Logger.info("cannot find the module definition of __MODULE__ in #{alias_line}")
      :error
    end
  end

  defp full(quoted, original) do
    [head | tail] = original

    with true <- current_module_as_atom?(head),
         {:__MODULE__, position, _} = head,
         {:ok, aliases} <- fetch_aliases_of_current_module(quoted, position[:line]) do
      Module.concat(aliases ++ tail)
    else
      _ -> Module.concat(original)
    end
  end

  defp current_module_as_atom?(module) do
    match?({:__MODULE__, _, _}, module)
  end
end
