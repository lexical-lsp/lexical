defmodule Lexical.RemoteControl.Api do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeAction
  alias Lexical.RemoteControl.CodeIntelligence
  alias Lexical.RemoteControl.CodeMod
  alias Lexical.RemoteControl.Commands

  require Logger

  defdelegate schedule_compile(project, force?), to: Build
  defdelegate compile_document(project, document), to: Build

  def expand_alias(
        %Project{} = project,
        segments_or_module,
        %Analysis{} = analysis,
        %Position{} = position
      ) do
    RemoteControl.call(project, RemoteControl.Analyzer, :expand_alias, [
      segments_or_module,
      analysis,
      position
    ])
  end

  def list_modules(%Project{} = project) do
    RemoteControl.call(project, :code, :all_available)
  end

  def format(%Project{} = project, %Document{} = document) do
    RemoteControl.call(project, CodeMod.Format, :edits, [document])
  end

  def code_actions(
        %Project{} = project,
        %Document{} = document,
        %Range{} = range,
        diagnostics,
        kinds
      ) do
    RemoteControl.call(project, CodeAction, :for_range, [document, range, diagnostics, kinds])
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

  def complete_struct_fields(%Project{} = project, %Analysis{} = analysis, %Position{} = position) do
    RemoteControl.call(project, RemoteControl.Completion, :struct_fields, [
      analysis,
      position
    ])
  end

  def definition(%Project{} = project, %Document{} = document, %Position{} = position) do
    RemoteControl.call(project, CodeIntelligence.Definition, :definition, [
      document,
      position
    ])
  end

  def references(
        %Project{} = project,
        %Analysis{} = analysis,
        %Position{} = position,
        include_definitions?
      ) do
    RemoteControl.call(project, CodeIntelligence.References, :references, [
      analysis,
      position,
      include_definitions?
    ])
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

  def reindex(%Project{} = project) do
    RemoteControl.call(project, Commands.Reindex, :perform, [])
  end

  def index_running?(%Project{} = project) do
    RemoteControl.call(project, Commands.Reindex, :running?, [])
  end

  def resolve_entity(%Project{} = project, %Analysis{} = analysis, %Position{} = position) do
    RemoteControl.call(project, CodeIntelligence.Entity, :resolve, [analysis, position])
  end

  def struct_definitions(%Project{} = project) do
    RemoteControl.call(project, CodeIntelligence.Structs, :for_project, [])
  end

  def document_symbols(%Project{} = project, %Document{} = document) do
    RemoteControl.call(project, CodeIntelligence.Symbols, :for_document, [document])
  end

  def workspace_symbols(%Project{} = project, query) do
    RemoteControl.call(project, CodeIntelligence.Symbols, :for_workspace, [query])
  end
end
