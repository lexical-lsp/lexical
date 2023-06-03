defmodule Lexical.Project.Diagnostics.StateTest do
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Plugin.Diagnostic
  alias Lexical.Project
  alias Lexical.Server.Project.Diagnostics.State

  import Lexical.Test.Fixtures

  use Lexical.Test.CodeMod.Case

  setup do
    {:ok, _} = start_supervised(Lexical.Document.Store)

    project = project()
    state = State.new(project)
    {:ok, project: project(), state: state}
  end

  def existing_file_path do
    Path.join([Project.root_path(project()), "lib", "project.ex"])
  end

  def document(contents, file_path \\ existing_file_path()) do
    file_uri = Document.Path.to_uri(file_path)

    with :ok <- Document.Store.open(file_uri, contents, 0),
         {:ok, document} <- Document.Store.fetch(file_uri) do
      document
    end
  end

  def change_with(document, content) do
    changes = [Edit.new(content)]

    {:ok, document} =
      Document.Store.get_and_update(
        document.uri,
        &Document.apply_content_changes(&1, 2, changes)
      )

    document
  end

  def compiler_diagnostic(opts \\ []) do
    file_uri =
      opts
      |> Keyword.get(:file, existing_file_path())
      |> Document.Path.ensure_uri()

    position = Keyword.get(opts, :position, 1)
    message = Keyword.get(opts, :message, "This file is broken")
    severity = Keyword.get(opts, :severity, :error)
    Diagnostic.Result.new(file_uri, position, message, severity, "Elixir")
  end

  test "it allows you to add a global diagnostic", %{state: state} do
    diagnostic = compiler_diagnostic(message: "This code is awful")

    state = State.add(state, diagnostic)

    assert [%Diagnostic.Result{}] = State.get(state, diagnostic.uri)
  end

  describe "clear_all_flushed/1" do
    test "it should not clear a dirty open file", %{state: state} do
      document =
        "hello"
        |> document()
        |> change_with("hello2")

      state = State.add(state, compiler_diagnostic(message: "The code is awful"))

      old_diagnostics = State.get(state, document.uri)
      state = State.clear_all_flushed(state)
      assert ^old_diagnostics = State.get(state, document.uri)
    end

    test "it should not clear a script file even if it is clean", %{
      state: state,
      project: project
    } do
      script_file_path = Path.join([Project.root_path(project), "test", "*.exs"])
      document = document("assert f() == 0", script_file_path)

      state = State.add(state, compiler_diagnostic(message: "undefined function f/0"))

      old_diagnostics = State.get(state, document.uri)
      state = State.clear_all_flushed(state)
      assert ^old_diagnostics = State.get(state, document.uri)
    end

    test "it should clear a file's diagnostics if it is just open", %{state: state} do
      document = document("hello")

      state = State.add(state, compiler_diagnostic(message: "The code is awful"))

      state = State.clear_all_flushed(state)
      diagnostics = State.get(state, document.uri)

      assert diagnostics == []
    end

    test "it should clear a file's diagnostics if it is closed", %{state: state} do
      document = document("hello")

      state = State.add(state, compiler_diagnostic(message: "The code is awful"))

      :ok = Document.Store.close(document.uri)

      state = State.clear_all_flushed(state)
      diagnostics = State.get(state, document.uri)

      assert diagnostics == []
    end
  end
end
