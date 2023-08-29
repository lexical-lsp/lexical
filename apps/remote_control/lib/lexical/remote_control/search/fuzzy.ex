defmodule Lexical.RemoteControl.Search.Fuzzy do
  @moduledoc """
  A backend for fuzzy matching

  Fuzzy is a storage module that allows fast mappings from patterns to lists of references.
  The references can then be used to consult a store to find their backing entities.
  """

  alias Lexical.RemoteControl.Search.Fuzzy.Scorer
  alias Lexical.RemoteControl.Search.Indexer.Entry

  defstruct subject_to_refs: %{}, path_to_refs: %{}, preprocessed_subjects: %{}

  @type subject :: String.t()
  @type entry :: {String.t(), reference()}
  @type t :: %__MODULE__{
          subject_to_refs: %{subject() => [reference()]},
          path_to_refs: %{Path.t() => [reference()]}
        }

  @spec new([Entry.t()]) :: t
  def new(entries) do
    subject_to_refs = Enum.group_by(entries, &stringify(&1.subject), & &1.ref)
    path_to_refs = Enum.group_by(entries, & &1.path, & &1.ref)

    preprocessed_subjects =
      subject_to_refs
      |> Map.keys()
      |> Map.new(fn subject -> {subject, Scorer.preprocess(subject)} end)

    %__MODULE__{
      subject_to_refs: subject_to_refs,
      path_to_refs: path_to_refs,
      preprocessed_subjects: preprocessed_subjects
    }
  end

  @spec match(t(), String.t()) :: [reference()]
  def match(%__MODULE__{} = fuzzy, pattern) do
    fuzzy.subject_to_refs
    |> Stream.map(fn {subject, references} ->
      case score(fuzzy, subject, pattern) do
        {:ok, score} ->
          {score, references}

        :error ->
          nil
      end
    end)
    |> Stream.reject(&is_nil/1)
    |> Enum.to_list()
    |> List.keysort(0)
    |> Enum.flat_map(&elem(&1, 1))
  end

  def add(%__MODULE__{} = fuzzy, %Entry{} = entry) do
    updated_path_to_refs =
      Map.update(fuzzy.path_to_refs, entry.path, [entry.ref], fn old_refs ->
        [entry.ref | old_refs]
      end)

    string_subject = stringify(entry.subject)

    updated_subject_to_refs =
      Map.update(fuzzy.subject_to_refs, string_subject, [entry.ref], fn old_refs ->
        [entry.ref | old_refs]
      end)

    updated_preprocessed_subjects =
      Map.put_new_lazy(fuzzy.preprocessed_subjects, string_subject, fn ->
        Scorer.preprocess(string_subject)
      end)

    %__MODULE__{
      fuzzy
      | path_to_refs: updated_path_to_refs,
        subject_to_refs: updated_subject_to_refs,
        preprocessed_subjects: updated_preprocessed_subjects
    }
  end

  def has_path?(%__MODULE__{} = fuzzy, path) do
    Map.has_key?(fuzzy.path_to_refs, path)
  end

  def has_subject?(%__MODULE__{} = fuzzy, subject) when is_binary(subject) do
    Map.has_key?(fuzzy.subject_to_refs, subject)
  end

  def has_subject?(%__MODULE__{} = fuzzy, subject) do
    has_subject?(fuzzy, inspect(subject))
  end

  def delete_path(%__MODULE__{} = fuzzy, path) do
    refs = Map.get(fuzzy.path_to_refs, path, [])
    fuzzy = drop_refs(fuzzy, refs)
    %__MODULE__{fuzzy | path_to_refs: Map.delete(fuzzy.path_to_refs, path)}
  end

  def drop_refs(%__MODULE__{} = fuzzy, refs) do
    ref_mapset = MapSet.new(refs)

    reject_refs = fn {subject, refs} ->
      {subject, Enum.reject(refs, &MapSet.member?(ref_mapset, &1))}
    end

    empty_refs? = fn
      {_, []} -> true
      {_, _} -> false
    end

    subject_to_refs =
      fuzzy.subject_to_refs
      |> Stream.map(reject_refs)
      |> Stream.reject(empty_refs?)
      |> Map.new()

    all_subjects =
      subject_to_refs
      |> Map.keys()
      |> MapSet.new()

    path_to_refs =
      fuzzy.path_to_refs
      |> Stream.map(reject_refs)
      |> Stream.reject(empty_refs?)
      |> Map.new()

    preprocessed_subjects =
      fuzzy.preprocessed_subjects
      |> Stream.filter(fn {subject, _} ->
        MapSet.member?(all_subjects, subject)
      end)
      |> Map.new()

    %__MODULE__{
      fuzzy
      | subject_to_refs: subject_to_refs,
        path_to_refs: path_to_refs,
        preprocessed_subjects: preprocessed_subjects
    }
  end

  def update(%__MODULE__{} = fuzzy, entries) do
    Enum.reduce(entries, fuzzy, fn entry, fuzzy ->
      add(fuzzy, entry)
    end)
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

  defp stringify(thing) do
    inspect(thing)
  end
end
