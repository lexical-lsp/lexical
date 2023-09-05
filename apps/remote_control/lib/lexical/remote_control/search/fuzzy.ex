defmodule Lexical.RemoteControl.Search.Fuzzy do
  @moduledoc """
  A backend for fuzzy matching

  This is a storage module that allows you to map keys to multiple values in two ways.

  Values are grouped by their `subject`, which is a string that enables fuzzy matching. They can also be grouped
  by a `grouping key` that allows for grouping by an arbitrary value.

  For both cases, multiple values can exist under the same key, and when searching, all values under the key are
  returned.
  """

  alias Lexical.RemoteControl.Search.Fuzzy.Scorer
  alias Lexical.RemoteControl.Search.Indexer.Entry

  defstruct subject_to_values: %{},
            grouping_key_to_values: %{},
            preprocessed_subjects: %{},
            mapper: nil,
            subject_converter: nil

  @type subject :: String.t()
  @type extracted_subject :: term()
  @type grouping_key :: term()
  @type value :: term()
  @type extracted_subject_grouping_key_value :: {extracted_subject(), grouping_key(), value()}
  @type mapper :: (term -> extracted_subject_grouping_key_value)
  @type subject_converter :: (extracted_subject() -> subject())

  @opaque t :: %__MODULE__{
            subject_to_values: %{subject() => [value()]},
            grouping_key_to_values: %{Path.t() => [value()]},
            preprocessed_subjects: %{subject() => tuple()},
            mapper: mapper(),
            subject_converter: subject_converter()
          }

  @spec from_entries([Entry.t()]) :: t
  def from_entries(entries) do
    mapper = fn %Entry{} = entry ->
      {entry.subject, entry.path, entry.ref}
    end

    new(entries, mapper, &stringify/1)
  end

  @doc """
  Creates a new fuzzy matcher.

  Items in the enumerable first argument will have the mapper function applied to them.
  For each tuple returned, the first element will then have the subject converter applied.
  This will produce a subject, which is what the `match/2` function uses for fuzzy matching.
  """
  @spec new([term()], mapper(), subject_converter()) :: t
  def new(items, mapper, subject_converter) do
    subject_grouping_key_values = Enum.map(items, mapper)

    extract_and_fix_subject = fn {subject, _, _} -> subject_converter.(subject) end

    subject_to_values =
      Enum.group_by(subject_grouping_key_values, extract_and_fix_subject, &elem(&1, 2))

    grouping_key_to_values =
      Enum.group_by(subject_grouping_key_values, &elem(&1, 1), &elem(&1, 2))

    preprocessed_subjects =
      subject_to_values
      |> Map.keys()
      |> Map.new(fn subject -> {subject, Scorer.preprocess(subject)} end)

    %__MODULE__{
      subject_to_values: subject_to_values,
      grouping_key_to_values: grouping_key_to_values,
      preprocessed_subjects: preprocessed_subjects,
      mapper: mapper,
      subject_converter: subject_converter
    }
  end

  @doc """
  Applies fuzzy matching to the pattern.

  Values that match will be aggregated and returned sorted
  in descending order of the match relevance. Items at the beginning of the list
  will have a higher score than items at the end.
  """
  @spec match(t(), String.t()) :: [reference()]
  def match(%__MODULE__{} = fuzzy, pattern) do
    fuzzy.subject_to_values
    |> Stream.map(fn {subject, references} ->
      case score(fuzzy, subject, pattern) do
        {:ok, score} ->
          {score, references}

        :error ->
          nil
      end
    end)
    |> Stream.reject(&is_nil/1)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.flat_map(&elem(&1, 1))
  end

  @doc """
  Adds a single item or a list of items to the fuzzy instance.
  """
  @spec add(t, term | [term]) :: t
  def add(%__MODULE__{} = fuzzy, items) when is_list(items) do
    Enum.reduce(items, fuzzy, fn entry, fuzzy ->
      add(fuzzy, entry)
    end)
  end

  def add(%__MODULE__{} = fuzzy, item) do
    {extracted_subject, grouping_key, value} = fuzzy.mapper.(item)
    subject = fuzzy.subject_converter.(extracted_subject)

    updated_grouping_key_to_values =
      Map.update(fuzzy.grouping_key_to_values, grouping_key, [value], fn old_refs ->
        [value | old_refs]
      end)

    updated_subject_to_values =
      Map.update(fuzzy.subject_to_values, subject, [value], fn old_refs ->
        [value | old_refs]
      end)

    updated_preprocessed_subjects =
      Map.put_new_lazy(fuzzy.preprocessed_subjects, subject, fn ->
        Scorer.preprocess(subject)
      end)

    %__MODULE__{
      fuzzy
      | grouping_key_to_values: updated_grouping_key_to_values,
        subject_to_values: updated_subject_to_values,
        preprocessed_subjects: updated_preprocessed_subjects
    }
  end

  @doc """
  Returns true if the fuzzy instance has the specified grouping_key
  """
  @spec has_grouping_key?(t, grouping_key()) :: boolean
  def has_grouping_key?(%__MODULE__{} = fuzzy, grouping_key) do
    Map.has_key?(fuzzy.grouping_key_to_values, grouping_key)
  end

  @doc """
  Returns true if the fuzzy instance has the specified subject.

  If the subject is a string, the conversion function passed into the
  constructor will be applied to the `subject` parameter.
  """
  @spec has_subject?(t, extracted_subject() | subject()) :: boolean
  def has_subject?(%__MODULE__{} = fuzzy, subject) when is_binary(subject) do
    Map.has_key?(fuzzy.subject_to_values, subject)
  end

  def has_subject?(%__MODULE__{} = fuzzy, subject) do
    has_subject?(fuzzy, fuzzy.subject_converter.(subject))
  end

  @spec delete_grouping_key(t, grouping_key()) :: t
  def delete_grouping_key(%__MODULE__{} = fuzzy, grouping_key) do
    values = Map.get(fuzzy.grouping_key_to_values, grouping_key, [])
    fuzzy = drop_values(fuzzy, values)

    %__MODULE__{
      fuzzy
      | grouping_key_to_values: Map.delete(fuzzy.grouping_key_to_values, grouping_key)
    }
  end

  @spec drop_values(t, [value()]) :: t
  def drop_values(%__MODULE__{} = fuzzy, []) do
    # a little optimization; drop_values is pretty expensive, and it's used in
    # delete_grouping_key. If there is nothing to delete, we should just return the fuzzy
    # unmodified.
    fuzzy
  end

  @doc """
  Removes all the given values from the data structure.

  If dropping the values results in a subject or grouping key having no entries in the data structure,
  the subject or grouping key is also removed.
  """
  def drop_values(%__MODULE__{} = fuzzy, values) do
    values_mapset = MapSet.new(values)

    reject_values = fn {subject, values} ->
      {subject, Enum.reject(values, &MapSet.member?(values_mapset, &1))}
    end

    empty_values? = fn
      {_, []} -> true
      {_, _} -> false
    end

    subject_to_values =
      fuzzy.subject_to_values
      |> Stream.map(reject_values)
      |> Stream.reject(empty_values?)
      |> Map.new()

    all_subjects =
      subject_to_values
      |> Map.keys()
      |> MapSet.new()

    grouping_key_to_values =
      fuzzy.grouping_key_to_values
      |> Stream.map(reject_values)
      |> Stream.reject(empty_values?)
      |> Map.new()

    preprocessed_subjects =
      fuzzy.preprocessed_subjects
      |> Stream.filter(fn {subject, _} ->
        MapSet.member?(all_subjects, subject)
      end)
      |> Map.new()

    %__MODULE__{
      fuzzy
      | subject_to_values: subject_to_values,
        grouping_key_to_values: grouping_key_to_values,
        preprocessed_subjects: preprocessed_subjects
    }
  end

  defp score(%__MODULE__{} = fuzzy, subject, pattern) do
    with {:ok, preprocessed} <- Map.fetch(fuzzy.preprocessed_subjects, subject),
         {true, score} <- Scorer.score(preprocessed, pattern) do
      {:ok, score}
    else
      _ ->
        :error
    end
  end

  defp stringify(string) when is_binary(string) do
    string
  end

  defp stringify(thing) do
    inspect(thing)
  end
end
