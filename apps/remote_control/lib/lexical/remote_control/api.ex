defmodule Lexical.RemoteControl.Api do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeMod
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position
  require Logger

  defdelegate schedule_compile(project, force?), to: Build
  defdelegate compile_source_file(project, source_file), to: Build

  def list_modules(%Project{} = project) do
    RemoteControl.call(project, :code, :all_available)
  end

  def format(%Project{} = project, %SourceFile{} = source_file) do
    RemoteControl.call(project, CodeMod.Format, :text_edits, [project, source_file])
  end

  def replace_with_underscore(
        %Project{} = project,
        %SourceFile{} = source_file,
        line_number,
        variable_name
      ) do
    RemoteControl.call(project, CodeMod.ReplaceWithUnderscore, :text_edits, [
      source_file,
      line_number,
      variable_name
    ])
  end

  def complete(%Project{} = project, %SourceFile{} = source_file, %Position{} = position) do
    source_string = SourceFile.to_string(source_file)
    complete(project, source_string, position)
  end

  def complete(%Project{} = project, source_string, %Position{} = position) do
    Logger.info("Completion for #{inspect(position)}")

    RemoteControl.call(project, Lexical.RemoteControl.Completion, :elixir_sense_expand, [
      source_string,
      position
    ])
  end
end
