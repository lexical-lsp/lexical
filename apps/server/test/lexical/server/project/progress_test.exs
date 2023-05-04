defmodule Lexical.Server.Project.ProgressTest do
  alias Lexical.Protocol.Notifications.CreateWorkDoneProgress
  alias Lexical.Protocol.Notifications.Progress, as: LSProgress
  alias Lexical.RemoteControl
  alias Lexical.Server.Project
  alias Lexical.Server.Transport

  import Lexical.Test.Fixtures
  import RemoteControl.Api.Messages

  use ExUnit.Case
  use Patch
  use Testing.EventualAssertions

  setup do
    project = project()

    {:ok, _} = start_supervised({Project.Dispatch, project})
    {:ok, _} = start_supervised({Project.Progress, project})

    {:ok, project: project}
  end

  def progress(label, message \\ "") do
    project_progress(label: label, message: message)
  end

  def with_patched_tranport(_) do
    test = self()

    patch(Transport, :write, fn message ->
      send(test, {:transport, message})
    end)

    :ok
  end

  describe "report the progress message" do
    setup [:with_patched_tranport]

    test "it should be able to send the report progress", %{project: project} do
      begin_message = progress("mix compile.begin")
      Project.Dispatch.broadcast(project, begin_message)

      assert_receive {:transport, %CreateWorkDoneProgress{lsp: %{token: token}}}
      assert_receive {:transport, %LSProgress{}}

      report_message = progress("mix compile", "lib/file.ex")
      Project.Dispatch.broadcast(project, report_message)
      assert_receive {:transport, %LSProgress{lsp: %{token: ^token, value: value}}}

      assert value.kind == :report
      assert value.message == "lib/file.ex"
      assert value.percentage == nil
      assert value.cancellable == nil
    end
  end
end
