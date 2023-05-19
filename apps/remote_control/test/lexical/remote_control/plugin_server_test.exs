defmodule Lexical.RemoteControl.PluginServerTest do
  alias Lexical.Project
  alias Lexical.Enhancement
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.PluginServer

  alias Lexical.RemoteControl.Api.Messages

  import Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch

  test "it should publish the diagnostics after validating and enhancing" do
    test_pid = self()
    patch(RemoteControl, :notify_listener, fn diagnostics -> send(test_pid, diagnostics) end)

    start_supervised!(PluginServer)

    enhancement =
      Enhancement.new(
        project: "project",
        uri: "file:///path/to/file",
        type: :file,
        source: :credo,
        validate: fn -> true end,
        enhance: fn -> :enhanced end
      )

    PluginServer.run(enhancement)

    assert_receive file_diagnostics(
                     project: "project",
                     uri: "file:///path/to/file",
                     diagnostics: [:enhanced],
                     source: :credo
                   )
  end

  def with_plugged_credo_project do
    fixture_dir = Path.join(fixtures_path(), "plugged_credo_project")
    project = Project.new("file://#{fixture_dir}")

    {:ok, _} = start_supervised({ProjectNodeSupervisor, project})
    {:ok, _, _} = RemoteControl.start_link(project, self())

    {:ok, project}
  end
end
