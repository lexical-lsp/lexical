defmodule Lexical.RemoteControl.Api do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeIntelligence
  alias Lexical.RemoteControl.CodeMod

  require Logger

  defdelegate schedule_compile(project, force?), to: Build
  defdelegate compile_document(project, document), to: Build

  def list_modules(%Project{} = project) do
    RemoteControl.call(project, :code, :all_available)
  end

  def format(%Project{} = project, %Document{} = document) do
    RemoteControl.call(project, CodeMod.Format, :edits, [project, document])
  end

  def replace_with_underscore(
        %Project{} = project,
        %Document{} = document,
        line_number,
        variable_name
      ) do
    RemoteControl.call(project, CodeMod.ReplaceWithUnderscore, :edits, [
      document,
      line_number,
      variable_name
    ])
  end

  def complete(%Project{} = project, %Document{} = document, %Position{} = position) do
    document_string = Document.to_string(document)
    complete(project, document_string, position)
  end

  def complete(%Project{} = project, document_string, %Position{} = position) do
    Logger.info("Completion for #{inspect(position)}")

    RemoteControl.call(project, RemoteControl.Completion, :elixir_sense_expand, [
      document_string,
      position
    ])
  end

  def complete_struct_fields(%Project{} = project, %Document{} = document, %Position{} = position) do
    RemoteControl.call(project, RemoteControl.Completion, :struct_fields, [
      document,
      position
    ])
  end

  def definition(%Project{} = project, %Document{} = document, %Position{} = position) do
    RemoteControl.call(project, CodeIntelligence.Definition, :definition, [
      document,
      position
    ])
  end

  def references(%Project{} = project, resolved_reference) do
    RemoteControl.call(project, CodeIntelligence.References, :references, [resolved_reference])
  end

  def modules_with_prefix(%Project{} = project, prefix)
      when is_binary(prefix) or is_atom(prefix) do
    RemoteControl.call(project, RemoteControl.Modules, :with_prefix, [prefix])
  end

  def modules_with_prefix(%Project{} = project, prefix, predicate)
      when is_binary(prefix) or is_atom(prefix) do
    RemoteControl.call(project, RemoteControl.Modules, :with_prefix, [prefix, predicate])
  end

  @spec docs(Project.t(), module()) :: {:ok, CodeIntelligence.Docs.t()} | {:error, any()}
  def docs(%Project{} = project, module, opts \\ []) when is_atom(module) do
    RemoteControl.call(project, CodeIntelligence.Docs, :for_module, [module, opts])
  end

  def register_listener(%Project{} = project, listener_pid, message_types)
      when is_pid(listener_pid) and is_list(message_types) do
    RemoteControl.call(project, RemoteControl.Dispatch, :register_listener, [
      listener_pid,
      message_types
    ])
  end

  def broadcast(%Project{} = project, message) do
    RemoteControl.call(project, RemoteControl.Dispatch, :broadcast, [message])
  end
end
