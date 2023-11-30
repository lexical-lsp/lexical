defmodule Lexical.RemoteControl.Search.Indexer.Extractors.Module do
  @moduledoc """
  Extracts module references and definitions from AST
  """

  alias Lexical.Ast
  alias Lexical.Document.Position
  alias Lexical.ProcessCache
  alias Lexical.RemoteControl.Search.Indexer.Extractor

  @behaviour Extractor

  @impl Extractor
  def extract(node, extractor)

  # Elixir module definition or reference
  def extract({:__aliases__, _, segments} = node, %Extractor{} = extractor) do
    case fetch_module(segments, node, extractor) do
      {:ok, module} ->
        extract_module(module, node, extractor)

      :error ->
        extractor
    end
  end

  # Erlang module definition or reference, which are plain atoms
  def extract({:__block__, _, [atom_literal]} = node, %Extractor{} = extractor)
      when is_atom(atom_literal) do
    case fetch_erlang_module(atom_literal) do
      {:ok, module} ->
        extract_module(module, node, extractor)

      :error ->
        extractor
    end
  end

  def extract(_node, %Extractor{} = extractor) do
    extractor
  end

  defp extract_module(module, node, %Extractor{} = extractor) do
    {node, subtype, parent_kind} =
      case extractor.ancestors do
        [{:defmodule, _, [_, _]} = defmodule_node | _] ->
          {defmodule_node, :definition, :module}

        _ ->
          {node, :reference, :any}
      end

    Extractor.record_entry(
      extractor,
      node,
      :module,
      subtype,
      module,
      Application.get_application(module),
      parent_kind: parent_kind
    )
  end

  defp fetch_module(maybe_module, node, %Extractor{} = extractor) when is_list(maybe_module) do
    with %Position{} = position <- Ast.get_position(node, extractor.analysis),
         {:ok, module} <- Ast.expand_alias(maybe_module, extractor.analysis, position),
         true <- well_formed_module?(module) do
      {:ok, module}
    else
      _ -> :error
    end
  end

  defp well_formed_module?(Elixir), do: false

  defp well_formed_module?(module) do
    module |> Module.split() |> Enum.all?(&module_part?/1)
  end

  @starts_with_capital ~r/[A-Z]+/
  defp module_part?(part) when is_binary(part) do
    Regex.match?(@starts_with_capital, part)
  end

  defp module_part?(_), do: false

  defp fetch_erlang_module(maybe_erlang_module) do
    if available_module?(maybe_erlang_module) do
      {:ok, maybe_erlang_module}
    else
      :error
    end
  end

  defp available_module?(potential_module) do
    MapSet.member?(all_modules(), potential_module)
  end

  defp all_modules do
    ProcessCache.trans(:all_modules, fn ->
      MapSet.new(:code.all_available(), fn {module_charlist, _, _} ->
        List.to_atom(module_charlist)
      end)
    end)
  end
end
