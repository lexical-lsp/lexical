defmodule Lexical.RemoteControl.Api.Proxy.State do
  alias Lexical.Document
  alias Lexical.RemoteControl.Api
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Commands

  import Api.Messages
  import Api.Proxy.Records
  import Record

  defrecord :indexed, index: nil, value: nil
  defstruct initiator_pid: nil, buffer: []

  def new(initiator_pid) do
    %__MODULE__{initiator_pid: initiator_pid}
  end

  def add_mfa(%__MODULE__{} = state, mfa() = mfa_record) do
    %__MODULE__{state | buffer: [mfa_record | state.buffer]}
  end

  def add_message(%__MODULE__{} = state, message() = message_record) do
    %__MODULE__{state | buffer: [message_record | state.buffer]}
  end

  def flush(%__MODULE__{} = state) do
    {commands, messages} =
      state.buffer
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {item, index} -> indexed(index: index, value: item) end)
      |> Enum.split_with(fn indexed(value: value) -> match?(mfa(), value) end)

    {project_compile, document_compiles, reindex} = collapse_commands(commands)

    all_commands = [project_compile | Map.values(document_compiles)]

    all_commands
    |> Enum.concat(collapse_messages(messages, project_compile, document_compiles))
    |> Enum.filter(&match?(indexed(), &1))
    |> Enum.sort_by(fn
      indexed(index: index) ->
        index
    end)
    |> Enum.map(fn indexed(value: message) -> message end)
    |> then(fn commands ->
      case reindex do
        indexed(value: value) -> commands ++ [value]
        _ -> commands
      end
    end)
  end

  defp collapse_commands(commands) do
    # Rules for collapsing commands
    # 1. If there's a project compilation requested, remove all document compilations
    # 2. Formats can be dropped, as they're only valid for a short time.
    # 3. If there's a reindex, do it after the project compilation has finished

    initial_state = %{project_compiles: [], document_compiles: %{}, reindex: nil}

    grouped =
      commands
      |> Enum.reduce(
        initial_state,
        fn
          indexed(value: mfa(module: Build, function: :schedule_compile)) = indexed, acc ->
            Map.update(acc, :project_compiles, [indexed], &[indexed | &1])

          indexed(value: mfa(module: Build, function: :compile_document) = mfa) = indexed, acc ->
            mfa(arguments: [_, document]) = mfa
            uri = document.uri
            put_in(acc, [:document_compiles, uri], indexed)

          indexed(value: mfa(module: Commands.Reindex)) = indexed, acc ->
            Map.put(acc, :reindex, indexed)

          _, acc ->
            acc
        end
      )

    %{
      project_compiles: project_compiles,
      document_compiles: document_compiles,
      reindex: reindex
    } = grouped

    project_compile =
      Enum.reduce(project_compiles, nil, fn
        indexed(value: mfa(arguments: [_, true])) = indexed, _ ->
          indexed

        indexed(value: mfa(arguments: [true])) = indexed, _ ->
          indexed

        indexed() = indexed, nil ->
          indexed

        _, acc ->
          acc
      end)

    document_compiles =
      if project_compile do
        %{}
      else
        for {uri, indexed} <- document_compiles, Document.Store.open?(uri), into: %{} do
          {uri, indexed}
        end
      end

    {project_compile, document_compiles, reindex}
  end

  defp collapse_messages(messages, project_compile, document_compiles) do
    # Rules for collapsing messages
    # 1. If the message is document-centric, discard it if the document isn't open.
    # 2. It's probably safe to drop all file compile requested messages
    # 3. File diagnostics can be dropped if
    #   a. There is a document compile command for that uri
    #   b. There is a project compile requested
    # 4. Progress messages should still be sent to dispatch, even when buffering

    Enum.filter(messages, fn
      indexed(value: message(body: file_compile_requested())) ->
        false

      indexed(value: message(body: project_compile_requested())) ->
        false

      indexed(value: message(body: file_diagnostics(uri: uri))) ->
        not (Map.has_key?(document_compiles, uri) or
               match?(project_compile_requested(), project_compile))

      indexed(value: message(body: body)) ->
        case fetch_uri(body) do
          {:ok, uri} ->
            Document.Store.open?(uri)

          :error ->
            true
        end
    end)
  end

  defp fetch_uri(filesystem_event(uri: uri)), do: {:ok, uri}
  defp fetch_uri(file_changed(uri: uri)), do: {:ok, uri}
  defp fetch_uri(file_compile_requested(uri: uri)), do: {:ok, uri}
  defp fetch_uri(file_compiled(uri: uri)), do: {:ok, uri}
  defp fetch_uri(file_deleted(uri: uri)), do: {:ok, uri}
  defp fetch_uri(file_diagnostics(uri: uri)), do: {:ok, uri}
  defp fetch_uri(_), do: :error
end
