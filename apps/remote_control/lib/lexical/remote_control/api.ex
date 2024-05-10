defmodule Lexical.RemoteControl.Api do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Env
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api
  alias Lexical.RemoteControl.CodeIntelligence

  require Logger

  def schedule_compile(%Project{} = project, force?) do
    RemoteControl.call(project, Api.Local, :schedule_compile, [force?])
  end

  def compile_document(%Project{} = project, %Document{} = document) do
    RemoteControl.call(project, Api.Local, :compile_document, [document])
  end

  def expand_alias(
        %Project{} = project,
        segments_or_module,
        %Analysis{} = analysis,
        %Position{} = position
      ) do
    RemoteControl.call(project, Api.Local, :expand_alias, [
      segments_or_module,
      analysis,
      position
    ])
  end

  def list_modules(%Project{} = project) do
    RemoteControl.call(project, Api.Local, :list_modules)
  end

  def format(%Project{} = project, %Document{} = document) do
    RemoteControl.call(project, Api.Local, :format, [document])
  end

  def code_actions(
        %Project{} = project,
        %Document{} = document,
        %Range{} = range,
        diagnostics,
        kinds
      ) do
    RemoteControl.call(project, Api.Local, :code_actions, [document, range, diagnostics, kinds])
  end

  def complete(%Project{} = project, %Env{} = env) do
    Logger.info("Completion for #{inspect(env.position)}")
    RemoteControl.call(project, Api.Local, :complete, [env])
  end

  def complete_struct_fields(%Project{} = project, %Analysis{} = analysis, %Position{} = position) do
    RemoteControl.call(project, Api.Local, :complete_struct_fields, [
      analysis,
      position
    ])
  end

  def definition(%Project{} = project, %Document{} = document, %Position{} = position) do
    RemoteControl.call(project, Api.Local, :definition, [document, position])
  end

  def references(
        %Project{} = project,
        %Analysis{} = analysis,
        %Position{} = position,
        include_definitions?
      ) do
    RemoteControl.call(project, Api.Local, :references, [
      analysis,
      position,
      include_definitions?
    ])
  end

  def modules_with_prefix(%Project{} = project, prefix)
      when is_binary(prefix) or is_atom(prefix) do
    RemoteControl.call(project, Api.Local, :modules_with_prefix, [prefix])
  end

  def modules_with_prefix(%Project{} = project, prefix, predicate)
      when is_binary(prefix) or is_atom(prefix) do
    RemoteControl.call(project, Api.Local, :modules_with_prefix, [prefix, predicate])
  end

  @spec docs(Project.t(), module()) :: {:ok, CodeIntelligence.Docs.t()} | {:error, any()}
  def docs(%Project{} = project, module, opts \\ []) when is_atom(module) do
    RemoteControl.call(project, Api.Local, :docs, [module, opts])
  end

  def register_listener(%Project{} = project, listener_pid, message_types)
      when is_pid(listener_pid) and is_list(message_types) do
    RemoteControl.call(project, Api.Local, :register_listener, [
      listener_pid,
      message_types
    ])
  end

  def broadcast(%Project{} = project, message) do
    RemoteControl.call(project, Api.Local, :broadcast, [message])
  end

  def reindex(%Project{} = project) do
    RemoteControl.call(project, Api.Local, :reindex, [])
  end

  def index_running?(%Project{} = project) do
    RemoteControl.call(project, Api.Local, :index_running?, [])
  end

  def resolve_entity(%Project{} = project, %Analysis{} = analysis, %Position{} = position) do
    RemoteControl.call(project, Api.Local, :resolve_entity, [analysis, position])
  end

  def struct_definitions(%Project{} = project) do
    RemoteControl.call(project, Api.Local, :struct_definitions, [])
  end

  def document_symbols(%Project{} = project, %Document{} = document) do
    RemoteControl.call(project, Api.Local, :document_symbols, [document])
  end

  def workspace_symbols(%Project{} = project, query) do
    RemoteControl.call(project, Api.Local, :workspace_symbols, [query])
  end
end
