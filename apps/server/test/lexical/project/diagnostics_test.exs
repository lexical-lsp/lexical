defmodule Lexical.Project.DiagnosticsTest do
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

  def diagnostic(file_path) do
    %Compiler.Diagnostic{
      file: SourceFile.Path.ensure_path(file_path),
      severity: :error,
      message: "stuff broke",
      position: 1,
      compiler_name: "Elixir"
    }
  end

  def with_patched_tranport(_) do
    test = self()

    patch(Transport, :write, fn message ->
      send(test, {:transport, message})
    end)

    :ok
  end

  def with_an_open_source_file(%{project: project}) do
    uri = file_uri(project, "lib/project.ex")
    :ok = SourceFile.Store.open(uri, "defmodule Foo", 0)
    {:ok, source_file} = SourceFile.Store.fetch(uri)
    {:ok, source_file: source_file, uri: uri}
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
  end
end
