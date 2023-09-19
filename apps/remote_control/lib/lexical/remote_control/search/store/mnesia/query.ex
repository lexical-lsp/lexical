defmodule Lexical.RemoteControl.Search.Store.Mnesia.Query do
  alias Lexical.RemoteControl.Search.Store.Mnesia
  alias Lexical.RemoteControl.Search.Store.Mnesia.Schema

  import Schema,
    only: [row: 1, row_pattern: 1]

  # Querying
  def insert(entries) do
    rows = Enum.map(entries, &Schema.to_row/1)

    result =
      :mnesia.transaction(fn ->
        Enum.map(rows, &:mnesia.write(Mnesia, &1, :write))
      end)

    coerce_result(result, :ok)
  end

  def drop do
    case :mnesia.clear_table(Mnesia) do
      {:atomic, _} -> true
      _ -> false
    end
  end

  def select_all do
    accumulate_values = fn row(value: value), entries ->
      [value | entries]
    end

    selector = fn ->
      :mnesia.foldl(accumulate_values, [], Mnesia)
    end

    selector
    |> :mnesia.transaction()
    |> finder_result(&Function.identity/1)
  end

  def replace_all(entries) do
    drop()
    insert(entries)
    :ok
  end

  def delete_by_path(path) do
    pattern = row_pattern(path: path)

    delete_paths = fn ->
      to_delete =
        pattern
        |> :mnesia.index_match_object(:path)
        |> List.flatten()

      Enum.each(to_delete, &:mnesia.delete_object/1)

      to_delete
    end

    extractor = fn results ->
      Enum.map(results, &extract_value/1)
    end

    delete_paths
    |> :mnesia.transaction()
    |> coerce_result(extractor)
  end

  def find_by_subject(subject, type, subtype) do
    key_pattern = Schema.to_key(subject, type, subtype)
    pattern = row_pattern(key: key_pattern)

    matcher = fn ->
      :mnesia.match_object(pattern)
    end

    matcher
    |> :mnesia.transaction()
    |> finder_result(&extract_value/1)
  end

  def find_by_refs(references, type, subtype) do
    key = Schema.to_key(:_, type, subtype)

    index_matcher = fn ->
      Enum.map(references, fn reference ->
        pattern = row_pattern(key: key, ref: reference)
        :mnesia.index_match_object(pattern, :ref)
      end)
    end

    index_matcher
    |> :mnesia.transaction()
    |> finder_result(&List.flatten/1, &extract_value/1)
  end

  defp extract_value(row(value: value)), do: value

  defp coerce_result({:aborted, reason}, _) do
    {:error, reason}
  end

  defp coerce_result({:atomic, result}, fixup) when is_function(fixup, 1) do
    {:ok, fixup.(result)}
  end

  defp coerce_result({:atomic, _}, override) do
    override
  end

  defp finder_result(result, pre_mapper \\ &Function.identity/1, mapper)

  defp finder_result({:aborted, _}, _, _),
    do: []

  defp finder_result({:atomic, rows}, pre_mapper, mapper),
    do: rows |> pre_mapper.() |> Enum.map(mapper)
end
