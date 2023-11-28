defmodule Lexical.RemoteControl.Search.Indexer.Extractors.Module do
  @moduledoc """
  Extracts module references and definitions from AST
  """

  alias Lexical.Ast
  alias Lexical.ProcessCache
  alias Lexical.RemoteControl.Search.Indexer.Extractor
  alias Sourceror.Zipper

  @behaviour Extractor

  @impl Extractor
  def extract(zipper, extractor)

  # Elixir module definition or reference
  def extract(
        %Zipper{node: {:__aliases__, _, segments}} = zipper,
        %Extractor{} = extractor
      ) do
    case fetch_module(segments, extractor) do
      {:ok, module} ->
        extract_module(extractor, module, zipper)

      :error ->
        extractor
    end
  end

  # Erlang module definition or reference, which are plain atoms
  def extract(
        %Zipper{node: {:__block__, _, [atom_literal]}} = zipper,
        %Extractor{} = extractor
      )
      when is_atom(atom_literal) do
    case fetch_erlang_module(atom_literal) do
      {:ok, module} ->
        extract_module(extractor, module, zipper)

      :error ->
        extractor
    end
  end

  def extract(_zipper, %Extractor{} = extractor) do
    extractor
  end

  defp extract_module(%Extractor{} = extractor, module, %Zipper{} = zipper) do
    {zipper, subtype, parent_kind} =
      case Zipper.up(zipper) do
        %Zipper{node: {:defmodule, _, [_, _]}} = defmodule_zipper ->
          {defmodule_zipper, :definition, :module}

        _ ->
          {zipper, :reference, :any}
      end

    Extractor.record_entry(
      extractor,
      zipper,
      :module,
      subtype,
      module,
      Application.get_application(module),
      parent_kind: parent_kind
    )
  end

  defp fetch_module(maybe_module, %Extractor{current_scope: nil}) when is_list(maybe_module) do
    with true <- Enum.all?(maybe_module, &is_atom/1),
         module = Module.concat(maybe_module),
         true <- well_formed_module?(module) do
      {:ok, module}
    else
      _ -> :error
    end
  end

  defp fetch_module(maybe_module, %Extractor{} = extractor) when is_list(maybe_module) do
    %Extractor{analysis: analysis, current_scope: scope} = extractor

    with {:ok, module} <- Ast.expand_alias(maybe_module, analysis, scope.range.start),
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
