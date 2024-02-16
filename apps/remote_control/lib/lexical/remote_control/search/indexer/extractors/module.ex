defmodule Lexical.RemoteControl.Search.Indexer.Extractors.Module do
  @moduledoc """
  Extracts module references and definitions from AST
  """

  alias Lexical.Ast
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.ProcessCache
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer
  alias Lexical.RemoteControl.Search.Subject

  require Logger

  # extract a module definition
  def extract(
        {:defmodule, defmodule_meta,
         [{:__aliases__, module_name_meta, module_name}, module_block]},
        %Reducer{} = reducer
      ) do
    %Block{} = block = Reducer.current_block(reducer)

    case resolve_alias(reducer, module_name) do
      {:ok, aliased_module} ->
        module_position = Metadata.position(module_name_meta)
        range = to_range(reducer, module_name, module_position)

        entry =
          Entry.block_definition(
            reducer.analysis.document.path,
            block,
            Subject.module(aliased_module),
            :module,
            range,
            Application.get_application(aliased_module)
          )

        module_name_meta = Reducer.skip(module_name_meta)

        elem =
          {:defmodule, defmodule_meta,
           [{:__aliases__, module_name_meta, module_name}, module_block]}

        {:ok, entry, elem}

      _ ->
        :ignored
    end
  end

  # This matches an elixir module reference
  def extract({:__aliases__, metadata, maybe_module}, %Reducer{} = reducer)
      when is_list(maybe_module) do
    case module(reducer, maybe_module) do
      {:ok, module} ->
        start = Metadata.position(metadata)
        range = to_range(reducer, maybe_module, start)
        %Block{} = current_block = Reducer.current_block(reducer)

        entry =
          Entry.reference(
            reducer.analysis.document.path,
            current_block,
            Subject.module(module),
            :module,
            range,
            Application.get_application(module)
          )

        {:ok, entry}

      _ ->
        :ignored
    end
  end

  # This matches an erlang module, which is just an atom
  def extract({:__block__, metadata, [atom_literal]}, %Reducer{} = reducer)
      when is_atom(atom_literal) do
    case module(reducer, atom_literal) do
      {:ok, module} ->
        start = Metadata.position(metadata)
        %Block{} = current_block = Reducer.current_block(reducer)
        range = to_range(reducer, module, start)

        entry =
          Entry.reference(
            reducer.analysis.document.path,
            current_block,
            Subject.module(module),
            :module,
            range,
            Application.get_application(module)
          )

        {:ok, entry}

      :error ->
        :ignored
    end
  end

  def extract(_, _) do
    :ignored
  end

  defp resolve_alias(%Reducer{} = reducer, unresolved_alias) do
    {line, column} = reducer.position
    position = Position.new(reducer.analysis.document, line, column)

    RemoteControl.Analyzer.expand_alias(unresolved_alias, reducer.analysis, position)
  end

  defp module(%Reducer{} = reducer, maybe_module) when is_list(maybe_module) do
    with true <- Enum.all?(maybe_module, &module_part?/1),
         {:ok, resolved} <- resolve_alias(reducer, maybe_module) do
      {:ok, resolved}
    else
      _ ->
        human_location = Reducer.human_location(reducer)

        Logger.warning(
          "Could not expand module #{inspect(maybe_module)}. Please report this (at #{human_location})"
        )

        :error
    end
  end

  defp module(%Reducer{}, maybe_erlang_module) when is_atom(maybe_erlang_module) do
    if available_module?(maybe_erlang_module) do
      {:ok, maybe_erlang_module}
    else
      :error
    end
  end

  defp module(_, _), do: :error

  @protocol_module_attribue_names [:protocol, :for]

  @starts_with_capital ~r/[A-Z]+/
  defp module_part?(part) when is_atom(part) do
    Regex.match?(@starts_with_capital, Atom.to_string(part))
  end

  defp module_part?({:@, _, [{type, _, _} | _]}) when type in @protocol_module_attribue_names,
    do: true

  defp module_part?({:__MODULE__, _, context}) when is_atom(context), do: true

  defp module_part?(_), do: false

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

  # handles @protocol and @for in defimpl blocks
  defp to_range(%Reducer{} = reducer, [{:@, _, [{type, _, _} | _]} = attribute | segments], _)
       when type in @protocol_module_attribue_names do
    range = Sourceror.get_range(attribute)

    document = reducer.analysis.document
    module_length = segments |> Ast.Module.name() |> String.length()
    # add one because we're off by the @ sign
    end_column = range.end[:column] + module_length + 1

    Range.new(
      Position.new(document, range.start[:line], range.start[:column]),
      Position.new(document, range.end[:line], end_column)
    )
  end

  defp to_range(%Reducer{} = reducer, module_name, {line, column}) do
    document = reducer.analysis.document

    module_length =
      module_name
      |> Ast.Module.name()
      |> String.length()

    Range.new(
      Position.new(document, line, column),
      Position.new(document, line, column + module_length)
    )
  end
end
