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
    file_uri = SourceFile.Path.to_uri(existing_file_path())

    with :ok <- SourceFile.Store.open(file_uri, contents, 0),
         {:ok, source_file} <- SourceFile.Store.fetch(file_uri) do
      source_file
    end
  end

  def change_with(source_file, content) do
    changes = [%{range: nil, text: content}]

    {:ok, source_file} =
      SourceFile.Store.get_and_update(
        source_file.uri,
        &SourceFile.apply_content_changes(&1, 2, changes)
      )

    source_file
  end

  defp compiler_position({line, column}) do
    {compiler_position(line), compiler_position(column)}
  end

  defp compiler_position(line) do
    line + 1
  end

  def compiler_diagnostic(opts \\ []) do
    position =
      opts
      |> Keyword.get(:position, 4)
      |> compiler_position()

    %Compiler.Diagnostic{
      message: Keyword.get(opts, :message, "This file is broken"),
      file: Keyword.get(opts, :file, existing_file_path()),
      position: position,
      severity: Keyword.get(opts, :severity, :error),
      compiler_name: "Elixir"
    }
  end

  test "it allows you to add a global diagnostic", %{state: state} do
    diagnostic = compiler_diagnostic(message: "This code is awful")

    assert {:ok, state} = State.add(state, diagnostic)

    assert [%Diagnostic{}] = State.get(state, SourceFile.Path.to_uri(diagnostic.file))
  end

  test "it allows you to add a source file diagnostic", %{state: state} do
    diagnostic = compiler_diagnostic(message: "Does not compile")
    source_file = source_file("hello")
    {:ok, state} = State.add(state, diagnostic, source_file.uri)

    assert [%Diagnostic{}] = State.get(state, source_file.uri)
  end

  describe "conversions" do
    test "converts a position that is only a line number", %{state: state} do
      diagnostic = compiler_diagnostic(message: "This code is awful")
      {:ok, state} = State.add(state, diagnostic)

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

      {:ok, state} = State.add(state, diagnostic, source_file.uri)

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
      ]t

      source_file = source_file(source)
      diagnostic = compiler_diagnostic(message: "Hoo boy, this is a mess", position: {2, 9})

      {:ok, state} = State.add(state, diagnostic, source_file.uri)

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

  describe "clear_all_flushed/1" do
    test "it should not clear a dirty open file", %{state: state} do
      source_file = source_file("hello") |> change_with("hello2")

      {:ok, state} =
        State.add(state, compiler_diagnostic(message: "The code is awful"), source_file.uri)

      state = State.clear_all_flushed(state)
      diagnostics = State.get(state, source_file.uri)

      assert [_] = diagnostics
    end

    test "it should clear a file's diagnostics if it is just open", %{state: state} do
      source_file = source_file("hello")

      {:ok, state} =
        State.add(state, compiler_diagnostic(message: "The code is awful"), source_file.uri)

      state = State.clear_all_flushed(state)
      diagnostics = State.get(state, source_file.uri)

      assert diagnostics == []
    end

    test "it should clear a file's diagnostics if it is closed", %{state: state} do
      source_file = source_file("hello")

      {:ok, state} =
        State.add(state, compiler_diagnostic(message: "The code is awful"), source_file.uri)

      :ok = SourceFile.Store.close(source_file.uri)

      state = State.clear_all_flushed(state)
      diagnostics = State.get(state, source_file.uri)

      assert diagnostics == []
    end
  end
end
