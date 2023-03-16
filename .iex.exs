# Node.start(:"remsh@127.0.0.1")
# Node.set_cookie(:lexical)
# Node.connect(:"manager@127.0.0.1")

alias Lexical.RemoteControl
alias Lexical.SourceFile
alias Lexical.SourceFile.Position

defmodule Helpers do
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Project
  alias Lexical.Server.CodeIntelligence
  alias Lexical.SourceFile.Position

  def observer do
    :observer.start()
  end

  def observer(project) do
    project
    |> ensure_project()
    |> RemoteControl.call(:observer, :start)
  end

  def sf(text) do
    SourceFile.new("file:///file.ex", text, 0)
  end

  def pos(line, character) do
    Position.new(line, character)
  end

  def compile_project(project) do
    project
    |> ensure_project()
    |> RemoteControl.Api.schedule_compile(true)
  end

  def compile_file(project, source) when is_binary(source) do
    project
    |> ensure_project()
    |> compile_file(sf(source))
  end

  def compile_file(project, %SourceFile{} = source_file) do
    project
    |> ensure_project()
    |> RemoteControl.Api.compile_source_file(source_file)
  end

  def complete(project, source, context \\ nil)

  def complete(project, source, context) when is_binary(source) do
    case completion_position(source) do
      {:found, line, character} ->
        complete(project, sf(source), line, character, context)

      other ->
        other
    end
  end

  def complete(project, %SourceFile{} = source, line, character, context) do
    context =
      if is_nil(context) do
        Completion.Context.new(trigger_kind: nil)
      else
        context
      end

    position = pos(line, character)

    project
    |> ensure_project()
    |> CodeIntelligence.Completion.complete(source, position, context)
  end

  def connect do
    manager_name = manager_name()
    Node.start(:"r@127.0.0.1")
    Node.set_cookie(:lexical)
    Node.connect(:"#{manager_name}@127.0.0.1")
  end

  def project(project) when is_atom(project) do
    project_path =
      [File.cwd!(), "..", to_string(project)]
      |> Path.join()
      |> Path.expand()

    project_uri = "file://#{project_path}"
    Lexical.Project.new(project_uri)
  end

  def stop_project(project) do
    project
    |> ensure_project()
    |> Lexical.Server.Project.Supervisor.stop()
  end

  def start_project(project) do
    project
    |> ensure_project()
    |> Lexical.Server.Project.Supervisor.start()
  end

  defp manager_name do
    {:ok, names} = :erl_epmd.names()

    names
    |> Enum.map(fn {name, _port} -> List.to_string(name) end)
    |> Enum.find(&String.starts_with?(&1, "manager"))
  end

  defp completion_position(source_string) do
    source_string
    |> String.split(["\r\n", "\r", "\n"])
    |> Enum.with_index()
    |> Enum.reduce_while(:not_found, fn {line, line_number}, _ ->
      if String.contains?(line, "|") do
        index =
          line
          |> String.graphemes()
          |> Enum.find_index(&(&1 == "|"))

        {:halt, {:found, line_number, index}}
      else
        {:cont, :not_found}
      end
    end)
  end

  defp ensure_project(%Project{} = project) do
    project
  end

  defp ensure_project(project) when is_binary(project) do
    project
    |> String.to_atom()
    |> project()
  end

  defp ensure_project(project) when is_atom(project) do
    project(project)
  end
end

import Helpers
