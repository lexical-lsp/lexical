defmodule Lexical.Server.Project.DiagnosticsTest do
  alias Lexical.Project
  alias Lexical.Protocol.Notifications.PublishDiagnostics
  alias Lexical.Server.Project
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

  defp open_file(project, contents) do
    uri = file_uri(project, "lib/project.ex")
    :ok = SourceFile.Store.open(uri, contents, 0)
    {:ok, source_file} = SourceFile.Store.fetch(uri)
    source_file
  end

  describe "clearing diagnostics on compile" do
    setup [:with_patched_tranport]

    test "it clears a file's diagnostics if it's not dirty", %{
      project: project
    } do
      source_file = open_file(project, "defmodule Foo")

      file_diagnostics_message =
        file_diagnostics(diagnostics: [diagnostic(source_file.uri)], uri: source_file.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{}}

      SourceFile.Store.get_and_update(source_file.uri, &SourceFile.mark_clean/1)

      Project.Dispatch.broadcast(project, project_diagnostics(diagnostics: []))

      assert_receive {:transport, %PublishDiagnostics{diagnostics: nil}}
    end

    test "it clears a file's diagnostics if it has been closed", %{
      project: project
    } do
      source_file = open_file(project, "defmodule Foo")

      file_diagnostics_message =
        file_diagnostics(diagnostics: [diagnostic(source_file.uri)], uri: source_file.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{}}, 500

      SourceFile.Store.close(source_file.uri)
      Project.Dispatch.broadcast(project, project_diagnostics(diagnostics: []))

      assert_receive {:transport, %PublishDiagnostics{diagnostics: nil}}
    end

    test "it adds a diagnostic to the last line if they're out of bounds", %{project: project} do
      source_file = open_file(project, "defmodule Dummy do\n  .\nend\n")
      # only 3 lines in the file, but elixir compiler gives us a line number of 4
      diagnostic =
        diagnostic("lib/project.ex",
          position: {4, 1},
          message: "missing terminator: end (for \"do\" starting at line 1)"
        )

      file_diagnostics_message = file_diagnostics(diagnostics: [diagnostic], uri: source_file.uri)

      Project.Dispatch.broadcast(project, file_diagnostics_message)
      assert_receive {:transport, %PublishDiagnostics{lsp: %{diagnostics: [diagnostic]}}}, 500

      range = diagnostic.range
      assert range.start.line == 0
      assert range.start.character == 0
      assert range.end.line == 3
      assert range.end.character == 0
    end
  end
end
