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
    pid = start_supervised!({Project.Progress, project})
    DispatchFake.start()
    RemoteControl.Dispatch.register_listener(pid, project_progress())
    RemoteControl.Dispatch.register_listener(pid, percent_progress())

    {:ok, project: project}
  end

  def percent_begin(project, label, max) do
    message = percent_progress(stage: :begin, label: label, max: max)
    RemoteControl.Api.broadcast(project, message)
  end

  defp percent_report(project, label, delta, message \\ nil) do
    message = percent_progress(stage: :report, label: label, message: message, delta: delta)
    RemoteControl.Api.broadcast(project, message)
  end

  defp percent_complete(project, label, message) do
    message = percent_progress(stage: :complete, label: label, message: message)
    RemoteControl.Api.broadcast(project, message)
  end

  def progress(stage, label, message \\ "") do
    project_progress(label: label, message: message, stage: stage)
  end

  def with_patched_transport(_) do
    test = self()

    patch(Transport, :write, fn message ->
      send(test, {:transport, message})
    end)

    :ok
  end

  def with_work_done_progress_support(_) do
    patch(Configuration, :client_supports?, fn :work_done_progress -> true end)
    :ok
  end

  describe "report the progress message" do
    setup [:with_patched_transport]

    test "it should be able to send the report progress", %{project: project} do
      patch(Configuration, :client_supports?, fn :work_done_progress -> true end)

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
      patch(Configuration, :client_supports?, fn :work_done_progress -> false end)

      begin_message = progress(:begin, "mix compile")
      RemoteControl.Api.broadcast(project, begin_message)

      refute_receive {:transport, %Requests.CreateWorkDoneProgress{lsp: %{}}}
    end
  end

  describe "reporting a percentage progress" do
    setup [:with_patched_transport, :with_work_done_progress_support]

    test "it should be able to increment the percentage", %{project: project} do
      percent_begin(project, "indexing", 400)

      assert_receive {:transport, %Requests.CreateWorkDoneProgress{lsp: %{token: token}}}
      assert_receive {:transport, %Notifications.Progress{} = progress}

      assert progress.lsp.value.kind == "begin"
      assert progress.lsp.value.title == "indexing"
      assert progress.lsp.value.percentage == 0

      percent_report(project, "indexing", 100)

      assert_receive {:transport, %Notifications.Progress{lsp: %{token: ^token, value: value}}}
      assert value.kind == "report"
      assert value.percentage == 25
      assert value.message == nil

      percent_report(project, "indexing", 260, "Almost done")

      assert_receive {:transport, %Notifications.Progress{lsp: %{token: ^token, value: value}}}
      assert value.percentage == 90
      assert value.message == "Almost done"

      percent_complete(project, "indexing", "Indexing Complete")

      assert_receive {:transport, %Notifications.Progress{lsp: %{token: ^token, value: value}}}
      assert value.kind == "end"
      assert value.message == "Indexing Complete"
    end

    test "it caps the percentage at 100", %{project: project} do
      percent_begin(project, "indexing", 100)
      percent_report(project, "indexing", 1000)
      assert_receive {:transport, %Notifications.Progress{lsp: %{value: %{kind: "begin"}}}}
      assert_receive {:transport, %Notifications.Progress{lsp: %{value: value}}}
      assert value.kind == "report"
      assert value.percentage == 100
    end

    test "it only allows the percentage to grow", %{project: project} do
      percent_begin(project, "indexing", 100)
      assert_receive {:transport, %Notifications.Progress{lsp: %{value: %{kind: "begin"}}}}

      percent_report(project, "indexing", 10)

      assert_receive {:transport, %Notifications.Progress{lsp: %{value: value}}}
      assert value.kind == "report"
      assert value.percentage == 10

      percent_report(project, "indexing", -10)
      assert_receive {:transport, %Notifications.Progress{lsp: %{value: value}}}
      assert value.kind == "report"
      assert value.percentage == 10

      percent_report(project, "indexing", 5)
      assert_receive {:transport, %Notifications.Progress{lsp: %{value: value}}}
      assert value.kind == "report"
      assert value.percentage == 15
    end
  end
end
