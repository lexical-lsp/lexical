defmodule Lexical.RemoteControl.Api do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeIntelligence
  alias Lexical.RemoteControl.CodeMod
  alias Lexical.RemoteControl.PluginServer

  require Logger

  defdelegate schedule_compile(project, force?), to: Build
  defdelegate compile_document(project, document), to: Build

  def enhance_by_plugin(project) do
    RemoteControl.call(project, PluginServer, :enhance, [project])
  end

  def enhance_by_plugin(project, document) do
    RemoteControl.call(project, PluginServer, :enhance, [project, document])
  end

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

  def definition(%Project{} = project, %Document{} = document, %Position{} = position) do
    RemoteControl.call(project, CodeIntelligence.Definition, :definition, [
      document,
      position
    ])
  end
end
