defmodule Lexical.Server.Project.ProgressTest do
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Requests
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl
  alias Lexical.Server.Configuration
  alias Lexical.Server.Project
  alias Lexical.Server.Transport
  alias Lexical.Test.DispatchFake

  import Lexical.Test.Fixtures
  import RemoteControl.Api.Messages

  use ExUnit.Case
  use Patch
  use DispatchFake
  use Lexical.Test.EventualAssertions

  setup do
    project = project()
    DispatchFake.start()

    {:ok, _} = start_supervised({Project.Progress, project})

    {:ok, project: project}
  end

  def progress(stage, label, message \\ "") do
    project_progress(label: label, message: message, stage: stage)
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
      patch(Configuration, :supports?, fn :work_done_progress? -> true end)

      begin_message = progress(:begin, "mix compile")
      RemoteControl.Api.broadcast(project, begin_message)

      assert_receive {:transport, %Requests.CreateWorkDoneProgress{lsp: %{token: token}}}
      assert_receive {:transport, %Notifications.Progress{}}

      report_message = progress(:report, "mix compile", "lib/file.ex")
      RemoteControl.Api.broadcast(project, report_message)
      assert_receive {:transport, %Notifications.Progress{lsp: %{token: ^token, value: value}}}

      assert value.kind == "report"
      assert value.message == "lib/file.ex"
      assert value.percentage == nil
      assert value.cancellable == nil
    end

    test "it should write nothing when the client does not support work done", %{project: project} do
      patch(Configuration, :supports?, fn :work_done_progress? -> false end)

      begin_message = progress(:begin, "mix compile")
      RemoteControl.Api.broadcast(project, begin_message)

      refute_receive {:transport, %Requests.CreateWorkDoneProgress{lsp: %{}}}
    end
  end
end
