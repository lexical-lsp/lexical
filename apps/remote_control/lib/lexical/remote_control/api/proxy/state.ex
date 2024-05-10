defmodule Lexical.RemoteControl.Api.Proxy.State do
  alias Lexical.Document
  alias Lexical.Identifier
  alias Lexical.RemoteControl.Api
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Commands

  import Api.Messages
  import Api.Proxy.Records
  import Record

  defrecord :buffered, id: nil, message: nil, type: nil
  defstruct initiator_pid: nil, buffer: []

  def new(initiator_pid) do
    %__MODULE__{initiator_pid: initiator_pid}
  end

  def add_mfa(%__MODULE__{} = state, mfa() = mfa_record) do
    command = buffered(id: Identifier.next_global!(), message: mfa_record, type: :mfa)
    %__MODULE__{state | buffer: [command | state.buffer]}
  end

  def add_message(%__MODULE__{} = state, message() = message_record) do
    message = buffered(id: Identifier.next_global!(), message: message_record, type: :message)
    %__MODULE__{state | buffer: [message | state.buffer]}
  end

  def flush(%__MODULE__{} = state) do
    {commands, messages} = Enum.split_with(state.buffer, &match?(buffered(message: mfa()), &1))
    {project_compile, document_compiles, reindex} = collapse_commands(commands)

    all_commands = [reindex, project_compile | Map.values(document_compiles)]

    all_commands
    |> Enum.concat(collapse_messages(messages, project_compile, document_compiles))
    |> Enum.filter(&match?(buffered(), &1))
    |> Enum.sort_by(fn
      buffered(message: mfa(module: Commands.Reindex)) ->
        # atoms are always greater than integers, so this will go last
        :reindex

      buffered(id: id) ->
        id
    end)
    |> Enum.map(fn
      buffered(message: message) ->
        message
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
          buffered(message: mfa(module: Build, function: :schedule_compile)) = buffered, acc ->
            Map.update(acc, :project_compiles, [buffered], &[buffered | &1])

          buffered(message: mfa(module: Build, function: :compile_document) = mfa) = buffered,
          acc ->
            mfa(arguments: [_, document]) = mfa
            uri = document.uri
            put_in(acc, [:document_compiles, uri], buffered)

          buffered(message: mfa(module: Commands.Reindex)) = buffered, acc ->
            Map.put(acc, :reindex, buffered)

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
        buffered(message: mfa(arguments: [_, true])) = buffered, _ ->
          buffered

        buffered(message: mfa(arguments: [true])) = buffered, _ ->
          buffered

        buffered() = buffered, nil ->
          buffered

        _, acc ->
          acc
      end)

    document_compiles =
      if project_compile do
        %{}
      else
        for {uri, buffered} <- document_compiles, Document.Store.open?(uri), into: %{} do
          {uri, buffered}
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
      buffered(message: message(body: file_compile_requested())) ->
        false

      buffered(message: message(body: project_compile_requested())) ->
        false

      buffered(message: message(body: file_diagnostics(uri: uri))) ->
        not (Map.has_key?(document_compiles, uri) or
               match?(project_compile_requested(), project_compile))

      buffered(message: message(body: body)) ->
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
