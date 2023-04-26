defmodule Lexical.Project.Diagnostics.StateTest do
  alias Lexical.Project
  alias Lexical.Server.Project.Diagnostics.State
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Edit
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

  def source_file(contents, file_path \\ existing_file_path()) do
    file_uri = SourceFile.Path.to_uri(file_path)

    with :ok <- SourceFile.Store.open(file_uri, contents, 0),
         {:ok, source_file} <- SourceFile.Store.fetch(file_uri) do
      source_file
    end
  end

  def change_with(source_file, content) do
    changes = [Edit.new(content)]

    {:ok, source_file} =
      SourceFile.Store.get_and_update(
        source_file.uri,
        &SourceFile.apply_content_changes(&1, 2, changes)
      )

    source_file
  end

  def compiler_diagnostic(opts \\ []) do
    position = Keyword.get(opts, :position, 1)

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

    state = State.add(state, diagnostic)

    assert [%Compiler.Diagnostic{}] = State.get(state, SourceFile.Path.to_uri(diagnostic.file))
  end

  test "it allows you to add a mix error", %{state: state, project: project} do
    error = %Mix.Error{message: "bad stuff"}
    assert state = State.add(state, error)

    [%Compiler.Diagnostic{} = diagnostic] =
      State.get(state, SourceFile.Path.to_uri(project.mix_exs_uri))

    assert diagnostic.compiler_name == "Mix"
    assert diagnostic.message == error.message
  end

  describe "clear_all_flushed/1" do
    test "it should not clear a dirty open file", %{state: state} do
      source_file = source_file("hello") |> change_with("hello2")

      state = State.add(state, compiler_diagnostic(message: "The code is awful"))

      old_diagnostics = State.get(state, source_file.uri)
      state = State.clear_all_flushed(state)
      assert ^old_diagnostics = State.get(state, source_file.uri)
    end

    test "it should not clear a script file even if it is clean", %{
      state: state,
      project: project
    } do
      script_file_path = Path.join([Project.root_path(project), "test", "*.exs"])
      source_file = source_file("assert f() == 0", script_file_path)

      state = State.add(state, compiler_diagnostic(message: "undefined function f/0"))

      old_diagnostics = State.get(state, source_file.uri)
      state = State.clear_all_flushed(state)
      assert ^old_diagnostics = State.get(state, source_file.uri)
    end

    test "it should clear a file's diagnostics if it is just open", %{state: state} do
      source_file = source_file("hello")

      state = State.add(state, compiler_diagnostic(message: "The code is awful"))

      state = State.clear_all_flushed(state)
      diagnostics = State.get(state, source_file.uri)

      assert diagnostics == []
    end

    test "it should clear a file's diagnostics if it is closed", %{state: state} do
      source_file = source_file("hello")

      state = State.add(state, compiler_diagnostic(message: "The code is awful"))

      :ok = SourceFile.Store.close(source_file.uri)

      state = State.clear_all_flushed(state)
      diagnostics = State.get(state, source_file.uri)

      assert diagnostics == []
    end
  end
end
