defmodule Lexical.RemoteControl.PluginServerTest do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.PluginServer
  alias Lexical.RemoteControl.ProjectNodeSupervisor

  alias Lexical.RemoteControl.Api.Messages

  import Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch

  describe "Current project" do
    setup do
      test_pid = self()
      patch(RemoteControl, :notify_listener, fn diagnostics -> send(test_pid, diagnostics) end)
      start_supervised!(PluginServer)
      :ok
    end

    test "it should publish the diagnostics" do
      project = project()
      file_uri = "file:///path/to/file"
      document = Document.new(file_uri, ~s[IO.puts("Hello World");\n], 1)

      PluginServer.enhance(project, document)

      assert_receive file_diagnostics(
                       project: ^project,
                       uri: ^file_uri,
                       diagnostics: [diagnostic]
                     ),
                     500

      assert diagnostic.message == "Don't use ; to separate statements and expressions"
    end
  end

  def with_compiled_plugged_project(_) do
    fixture_dir = Path.join(fixtures_path(), "plugged_credo_project")
    project = Project.new("file://#{fixture_dir}")

    {:ok, _} = start_supervised({ProjectNodeSupervisor, project})
    {:ok, _, _} = RemoteControl.start_link(project, self())

    Build.schedule_compile(project, true)
    assert_receive project_compiled(status: :success), 10_000

    %{project: project}
  end

  describe "credo diagnostics" do
    setup :with_compiled_plugged_project

    test "it should publish the file diagnostics", %{project: project} do
      file_uri = "file:///path/to/file"
      document = Document.new(file_uri, ~s[IO.puts("Hello World");\n], 1)
      RemoteControl.call(project, PluginServer, :enhance, [project, document])

      assert_receive file_diagnostics(
                       project: ^project,
                       uri: ^file_uri,
                       diagnostics: [diagnostic]
                     ),
                     500

      assert diagnostic.message == "Don't use ; to separate statements and expressions"
    end

    test "it should publish project diagnostics", %{project: project} do
      RemoteControl.call(project, PluginServer, :enhance, [project])

      assert_receive project_diagnostics(
                       project: ^project,
                       diagnostics: [diagnostic],
                       from: "Credo"
                     ),
                     2000

      assert diagnostic.message == "One `Enum.filter/2` is more efficient than `Enum.filter/2 |> Enum.filter/2`"
    end
  end
end
