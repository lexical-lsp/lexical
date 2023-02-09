defmodule Lexical.Project.Diagnostics.StateTest do
  alias Lexical.Project
  alias Lexical.Protocol.Types.Diagnostic
  alias Lexical.Protocol.Types.Range
  alias Lexical.SourceFile
  alias Lexical.Server.Project.Diagnostics.State
  alias Mix.Task.Compiler

  import Lexical.Test.Fixtures

  use Lexical.Test.CodeMod.Case

  setup do
    {:ok, _} = start_supervised(Lexical.SourceFile.Store)

    project = project()
    state = State.new(project)
    {:ok, project: project(), state: state}
  end

  def existing_file_path do
    Path.join([Project.root_path(project()), "lib", "project.ex"])
  end

  def source_file(contents \\ "") do
    existing_file_path()
    |> SourceFile.Path.to_uri()
    |> SourceFile.new(contents, 0)
  end

  def compiler_diagnostic(opts \\ []) do
    %Compiler.Diagnostic{
      message: Keyword.get(opts, :message, "This file is broken"),
      file: Keyword.get(opts, :file, existing_file_path()),
      position: Keyword.get(opts, :position, 4),
      severity: Keyword.get(opts, :severity, :error),
      compiler_name: "Elixir"
    }
  end

  test "it allows you to add a global diagnostic", %{state: state} do
    diagnostic = compiler_diagnostic(message: "This code is awful")
    state = State.add(state, diagnostic)

    assert [%Diagnostic{}] = State.get(state, SourceFile.Path.to_uri(diagnostic.file))
  end

  test "it allows you to add a source file diagnostic", %{state: state} do
    diagnostic = compiler_diagnostic(message: "Does not compile")
    source_file = source_file("hello")
    state = State.add(state, diagnostic, source_file)

    assert [%Diagnostic{}] = State.get(state, source_file.uri)
  end

  describe "conversions" do
    test "converts a position that is only a line number", %{state: state} do
      diagnostic = compiler_diagnostic(message: "This code is awful")
      state = State.add(state, diagnostic)

      assert [%Diagnostic{} = proto_diagnostic] =
               State.get(state, SourceFile.Path.to_uri(diagnostic.file))

      assert proto_diagnostic.message == "This code is awful"
      range = proto_diagnostic.range

      # Starting at 0 and going to character 0 on the next line highlights the entire line
      assert range.start.line == diagnostic.position - 1
      assert range.start.character == 0

      assert range.end.line == diagnostic.position
      assert range.end.character == 0
    end

    test "converts a position that is a line and a column", %{state: state} do
      source = ~q[
      defmodule MyModule do
        def foo do

        end
      end
      ]
      source_file = source_file(source)
      diagnostic = compiler_diagnostic(message: "Hoo boy, this is a mess", position: {1, 5})

      state = State.add(state, diagnostic, source_file)

      assert [%Diagnostic{} = proto_diagnostic] =
               State.get(state, SourceFile.Path.to_uri(diagnostic.file))

      assert proto_diagnostic.message == "Hoo boy, this is a mess"

      %Range{} = range = proto_diagnostic.range

      # Starting at 0 and going to character 0 on the next line highlights the entire line
      assert range.start.line == 1
      assert range.start.character == 5

      assert range.end.line == 2
      assert range.end.character == 0
    end

    test "converts a position that is a line and a column handling emojis", %{state: state} do
      source = ~q[
      defmodule MyModule do
        def foo do
          "🎸hello"
        end
      end
      ]

      source_file = source_file(source)
      diagnostic = compiler_diagnostic(message: "Hoo boy, this is a mess", position: {2, 9})

      state = State.add(state, diagnostic, source_file)

      assert [%Diagnostic{} = proto_diagnostic] =
               State.get(state, SourceFile.Path.to_uri(diagnostic.file))

      assert proto_diagnostic.message == "Hoo boy, this is a mess"
      range = proto_diagnostic.range

      # Starting at 0 and going to character 0 on the next line highlights the entire line
      assert range.start.line == 2
      assert range.start.character == 7

      assert range.end.line == 3
      assert range.end.character == 0
    end
  end
end
