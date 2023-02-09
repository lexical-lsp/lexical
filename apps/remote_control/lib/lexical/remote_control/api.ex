defmodule Lexical.RemoteControl.Api do
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  require Logger

  defdelegate schedule_compile(project, force?), to: Build
  defdelegate compile_source_file(project, source_file), to: Build

  def list_modules(%Project{} = project) do
    RemoteControl.call(project, :code, :all_available)
  end

  def formatter_for_file(%Project{} = project, path) do
    {formatter, options} =
      RemoteControl.call(project, Mix.Tasks.Format, :formatter_for_file, [path])

    {:ok, formatter, options}
  end

  def formatter_options_for_file(%Project{} = project, path) do
    RemoteControl.call(project, Mix.Tasks.Format, :formatter_opts_for_file, [path])
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
