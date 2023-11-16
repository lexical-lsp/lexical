defmodule Lexical.RemoteControl.Search.Indexer.Extractors.Variable do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer
  require Logger

  def extract({:=, _assignment_meta, [left, _right]} = elem, %Reducer{} = reducer) do
    subject_with_ranges = left |> extract_from_left(reducer) |> List.wrap() |> List.flatten()
    entries = to_definition_entries(subject_with_ranges, reducer)
    {:ok, entries, elem}
  end

  def extract(_elem, %Reducer{} = _reducer) do
    :ignored
  end

  defp to_definition_entries(subject_with_ranges, %Reducer{} = reducer) do
    %Block{} = block = Reducer.current_block(reducer)
    %Analysis{document: document} = reducer.analysis

    for {subject, range} <- List.flatten(subject_with_ranges) do
      Entry.definition(
        document.path,
        make_ref(),
        block.ref,
        subject,
        :variable,
        range,
        get_application(document)
      )
    end
  end

  # «a» = 1
  defp extract_from_left({_variable, _meta, nil} = elem, reducer) do
    do_extract(elem, reducer)
  end

  # like: [«a, b»] = [1, 2] or {«a, b»} = [1, 2]
  defp extract_from_left(ast_list, reducer) when is_list(ast_list) do
    Enum.map(ast_list, fn ast -> extract_from_left(ast, reducer) end)
  end

  # def foo(a, «b \\ 2»)
  defp extract_from_left({:\\, _meta, [parameter, _default_value]}, reducer) do
    extract_from_left(parameter, reducer)
  end

  # «%{a: a, b: b}» = %{a: 1, b: 2}
  defp extract_from_left({:%{}, _map_metadata, fields}, reducer) do
    Enum.map(fields, fn
      {_key, value} ->
        extract_from_left(value, reducer)

      # %{unquote_splicing(list)}
      _ ->
        []
    end)
  end

  # «%Foo{a: a, b: b}» = %Foo{a: 1, b: 2}
  defp extract_from_left({:%, _map_metadata, [_struct_module_info, struct_block]}, reducer) do
    # struct_block is the same as «%{a: a, b: b}»
    extract_from_left(struct_block, reducer)
  end

  # «{:a, b, [c, d]}»
  defp extract_from_left({:{}, _, blocks_in_tuple}, reducer) do
    extract_from_left(blocks_in_tuple, reducer)
  end

  # «[a, b]» = [1, 2]
  defp extract_from_left({:__block__, _, [block]}, reducer) when is_list(block) do
    extract_from_left(block, reducer)
  end

  # «{a, b}» = [1, 2]
  defp extract_from_left({:__block__, _, [block]}, reducer) when is_tuple(block) do
    block = Tuple.to_list(block)
    extract_from_left(block, reducer)
  end

  # ignore some ast like: «a = 1», since the top function will handle it
  defp extract_from_left(_, _reducer) do
    []
  end

  defp to_range(%Document{} = document, variable, {line, column}) do
    variable_length = variable |> to_string() |> String.length()

    Range.new(
      Position.new(document, line, column),
      Position.new(document, line, column + variable_length)
    )
  end

  defp get_application(_document) do
    # NOTE_TO_MYSELF: I think we should calculate the application name based on the path of the file
    # and find the nearest mix.exs file and use that as the application name
    nil
  end

  defp do_extract({variable, meta, nil}, %Reducer{analysis: analysis}) do
    range = to_range(analysis.document, variable, Metadata.position(meta))
    {variable, range}
  end
end
