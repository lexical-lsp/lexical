# Node.start(:"remsh@127.0.0.1")
# Node.set_cookie(:lexical)
# Node.connect(:"manager@127.0.0.1")

alias Lexical.RemoteControl
alias Lexical.SourceFile
alias Lexical.SourceFile.Position

defmodule Helpers do
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Server.CodeIntelligence
  alias Lexical.SourceFile.Position

  def observer do
    :observer.start()
  end

  def observer(project) do
    RemoteControl.call(project, :observer, :start)
  end

  def sf(text) do
    SourceFile.new("file:///file.ex", text, 0)
  end

  def pos(line, character) do
    Position.new(line, character)
  end

  def compile_file(project, source) when is_binary(source) do
    compile_file(project, sf(source))
  end

  def compile_file(project, %SourceFile{} = source_file) do
    RemoteControl.Api.compile_source_file(project, source_file)
  end

  def complete(project, source, line, character, context \\ nil)

  def complete(project, %SourceFile{} = source, line, character, context) do
    context =
      if is_nil(context) do
        Completion.Context.new(trigger_kind: nil)
      else
        context
      end

    position = pos(line, character)
    CodeIntelligence.Completion.complete(project, source, position, context)
  end

  def complete(project, source, line, character, context) when is_binary(source) do
    complete(project, sf(source), line, character, context)
  end

  def connect do
    manager_name = manager_name()
    Node.start(:"r@127.0.0.1")
    Node.set_cookie(:lexical)
    Node.connect(:"#{manager_name}@127.0.0.1")
  end

  def start_project(project) do
    Lexical.Server.Project.Supervisor.start(project)
  end

  defp manager_name do
    {:ok, names} = :erl_epmd.names()

    names
    |> Enum.map(fn {name, _port} -> List.to_string(name) end)
    |> Enum.find(&String.starts_with?(&1, "manager"))
  end
end

error_source = """
defmodule Error do
  def error do
    a()
    b()
    c()
    x = 4
  end
end
"""

completion_source = """
defmodule Complete do
def foo do
Enum.f
"""

lexical = Lexical.Project.new("file://#{File.cwd!()}/")
eakins = Lexical.Project.new("file://#{File.cwd!()}/../eakins/")
sonato = Lexical.Project.new("file://#{File.cwd!()}/../spike/")
import Helpers
