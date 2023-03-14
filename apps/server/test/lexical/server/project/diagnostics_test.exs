defmodule Lexical.Server.Project.DiagnosticsTest do
  alias Lexical.Project
  alias Lexical.Protocol.Notifications.PublishDiagnostics
  alias Lexical.Server.Project
  alias Lexical.Server.Project.Diagnostics.State
  alias Lexical.Server.Transport
  alias Lexical.SourceFile
  alias Mix.Task.Compiler

  use ExUnit.Case
  use Patch

  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  setup do
    project = project()

    {:ok, _} = start_supervised(Lexical.SourceFile.Store)
    {:ok, _} = start_supervised({Project.Dispatch, project})
    {:ok, _} = start_supervised({Project.Diagnostics, project})

    {:ok, project: project}
  end

  def diagnostic(file_path, opts \\ []) do
    defaults = [
      file: SourceFile.Path.ensure_path(file_path),
      severity: :error,
      message: "stuff broke",
      position: 1,
      compiler_name: "Elixir"
    ]

    values = Keyword.merge(defaults, opts)
    struct(Compiler.Diagnostic, values)
  end

  def with_patched_tranport(_) do
    test = self()

    patch(Transport, :write, fn message ->
      send(test, {:transport, message})
    end)

    :ok
  end

  def with_an_open_source_file(%{project: project}, opts \\ []) do
    default_text = "defmodule Foo"
    uri = file_uri(project, "lib/project.ex")
    :ok = SourceFile.Store.open(uri, opts[:text] || default_text, 0)
    {:ok, source_file} = SourceFile.Store.fetch(uri)
    {:ok, source_file: source_file, uri: uri}
  end

  describe "adding diagnostics to state" do
    test "it adds a diagnostic to the last line if they're out of bounds", %{project: project} do
      with_an_open_source_file(%{project: project}, text: "defmodule Dummy do\n  .\nend\n")
      # only 3 lines in the file, but elixir compiler gives us a line number of 4
      diagnostic =
        diagnostic("lib/project.ex",
          position: {4, 1},
          message: "missing terminator: end (for \"do\" starting at line 1)"
        )

      {:ok, state} = project |> State.new() |> State.add(diagnostic)

      uri = Path.join(project.root_uri, "lib/project.ex")

      [%{range: diagnostic_range}] = state.diagnostics_by_uri[uri]
      assert diagnostic_range.start.line == 2
      assert diagnostic_range.end.line == 3
    end
  end

  describe "clearing diagnostics on compile" do
    setup [:with_patched_tranport, :with_an_open_source_file]

    test "it keeps a file's diagnostics if it is dirty", %{
      project: project,
      source_file: source_file,
      uri: uri
    } do
      file_diagnostics_message =
        file_diagnostics(diagnostics: [diagnostic(uri)], uri: source_file.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{} = publish_diagnostics}, 500

      [previous_diagnostic] = publish_diagnostics.lsp.diagnostics

      Project.Dispatch.broadcast(project, project_diagnostics(diagnostics: []))
      assert_receive {:transport, new_diagnostics}

      assert new_diagnostics.lsp.diagnostics == [previous_diagnostic]
    end

    test "it clears a file's diagnostics if it's not dirty", %{
      project: project,
      source_file: source_file,
      uri: uri
    } do
      file_diagnostics_message =
        file_diagnostics(diagnostics: [diagnostic(uri)], uri: source_file.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{}}

      SourceFile.Store.get_and_update(uri, &SourceFile.mark_clean/1)

      Project.Dispatch.broadcast(project, project_diagnostics(diagnostics: []))

      assert_receive {:transport, %PublishDiagnostics{diagnostics: nil}}
    end

    test "it clears a file's diagnostics if it has been closed", %{
      project: project,
      source_file: source_file,
      uri: uri
    } do
      file_diagnostics_message =
        file_diagnostics(diagnostics: [diagnostic(uri)], uri: source_file.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{}}, 500

      SourceFile.Store.close(uri)
      Project.Dispatch.broadcast(project, project_diagnostics(diagnostics: []))

      assert_receive {:transport, %PublishDiagnostics{diagnostics: nil}}
    end

    test "it converts a file's diagnostics to the first line if they're out of bounds", %{
      project: project,
      uri: uri
    } do
      file_diagnostics = diagnostic(uri, position: {100, 2})
      file_diagnostics_message = file_diagnostics(diagnostics: [file_diagnostics], uri: uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{lsp: %{diagnostics: [diagnostic]}}}, 500

      range = diagnostic.range

      assert range.start.line == 0
      assert range.end.line == 1
    end
  end
end
