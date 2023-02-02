defmodule Lexical.RemoteControl.Api do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build

  defdelegate schedule_compile(project, force?), to: Build
  defdelegate compile_source_file(project, source_file), to: Build

  def list_modules(%Project{} = project) do
    RemoteControl.call(project, :code, :all_available)
  end

  def formatter_for_file(%Project{} = project, path) do
    {formatter, _} = RemoteControl.call(project, Mix.Tasks.Format, :formatter_for_file, [path])
    formatter
  end
end
