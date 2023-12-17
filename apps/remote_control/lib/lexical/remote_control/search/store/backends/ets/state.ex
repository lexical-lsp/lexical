defmodule Lexical.RemoteControl.Search.Store.Backends.Ets.State do
  @moduledoc """
  An ETS based search backend

  This backend uses an ETS table to store its data using a schema defined in the schemas submodule.

  """
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schema
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas
  alias Lexical.VM.Versions

  @schema_order [
    Schemas.LegacyV0,
    Schemas.V1,
    Schemas.V2
  ]

  import Schemas.V1,
    only: [
      query_by_id: 0,
      query_by_id: 1,
      query_by_path: 1
    ]

  import Schemas.V2,
    only: [
      query_by_subject_prefix: 1
    ]

  defstruct [:project, :table_name, :leader?, :leader_pid]

  def new_leader(%Project{} = project) do
    %__MODULE__{project: project, leader?: true, leader_pid: self()}
  end

  def new_follower(%Project{} = project, leader_pid) do
    %__MODULE__{project: project, leader?: false, leader_pid: leader_pid}
  end

  def prepare(%__MODULE__{leader?: true} = state) do
    {:ok, table_name, result} = Schema.load(state.project, @schema_order)
    :ets.info(table_name)
    {{:ok, result}, %__MODULE__{state | table_name: table_name}}
  end

  def prepare(%__MODULE__{leader?: false}) do
    {:error, :not_leader}
  end

  def drop(%__MODULE__{leader?: true} = state) do
    :ets.delete_all_objects(state.table_name)
  end

  def insert(%__MODULE__{leader?: true} = state, entries) do
    rows = Schemas.V1.entries_to_rows(entries)
    true = :ets.insert(state.table_name, rows)
    :ok
  end

  def select_all(%__MODULE__{} = state) do
    state.table_name
    |> :ets.match({query_by_id(), :"$1"})
    |> List.flatten()
  end

  def find_by_prefix(%__MODULE__{} = state, subject, type, subtype) do
    versions = Versions.current()

    match_pattern =
      query_by_subject_prefix(
        subject: to_prefix(subject),
        type: type,
        subtype: subtype,
        elixir_version: versions.elixir,
        erlang_version: versions.erlang
      )

    state.table_name
    |> :ets.select([{{match_pattern, :_}, [], [:"$_"]}])
    |> Enum.flat_map(fn {_, match} -> match end)
  end

  def find_by_subject(%__MODULE__{} = state, subject, type, subtype) do
    versions = Versions.current()

    match_pattern =
      query_by_subject_prefix(
        subject: to_subject(subject),
        type: type,
        subtype: subtype,
        elixir_version: versions.elixir,
        erlang_version: versions.erlang
      )

    state.table_name
    |> :ets.match_object({match_pattern, :_})
    |> Enum.flat_map(fn {_, match} -> match end)
  end

  def find_by_references(%__MODULE__{} = state, references, type, subtype)
      when is_list(references) do
    versions = Versions.current()

    for reference <- references,
        match_pattern = match_id_key(reference, versions, type, subtype),
        {_key, entry} <- :ets.match_object(state.table_name, match_pattern) do
      entry
    end
    |> List.flatten()
  end

  def replace_all(%__MODULE__{leader?: true} = state, entries) do
    rows = Schemas.V1.entries_to_rows(entries)

    with true <- :ets.delete_all_objects(state.table_name),
         true <- :ets.insert(state.table_name, rows) do
      :ok
    end
  end

  def delete_by_path(%__MODULE__{leader?: true} = state, path) do
    ids_to_delete =
      state.table_name
      |> :ets.match({query_by_path(path: path), :"$0"})
      |> List.flatten()

    :ets.match_delete(state.table_name, {query_by_subject_prefix(path: path), :_})
    :ets.match_delete(state.table_name, {query_by_path(path: path), :_})
    Enum.each(ids_to_delete, &:ets.delete(state.table_name, &1))
    {:ok, ids_to_delete}
  end

  def destroy(%__MODULE__{leader?: true} = state) do
    destroy(state.project)
  end

  def destroy(%Project{} = project) do
    project
    |> Schema.index_root()
    |> File.rm_rf()
  end

  def sync(%__MODULE__{leader?: true} = state) do
    file_path_charlist =
      state.project
      |> Schema.index_file_path(current_schema())
      |> String.to_charlist()

    :ets.tab2file(state.table_name, file_path_charlist)
    state
  end

  def sync(%__MODULE__{leader?: false} = state) do
    state
  end

  defp match_id_key(reference, versions, type, subtype) do
    {query_by_id(
       id: reference,
       type: type,
       subtype: subtype,
       elixir_version: versions.elixir,
       erlang_version: versions.erlang
     ), :_}
  end

  defp to_subject(:_), do: :_
  defp to_subject(other), do: Schemas.V2.subject_to_charlist(other)

  @dialyzer {:nowarn_function, to_prefix: 1}

  defp to_prefix(prefix) when is_binary(prefix) do
    [last_char | others] = prefix |> String.to_charlist() |> Enum.reverse()
    others |> Enum.reverse() |> Enum.concat([last_char | :_])
  end

  defp current_schema do
    List.last(@schema_order)
  end
end
