defmodule Lexical.RemoteControl.Commands.RenameTest do
  alias Lexical.RemoteControl.Api.Proxy
  alias Lexical.RemoteControl.Commands.Rename
  alias Lexical.RemoteControl.Commands.RenameSupervisor

  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.EventualAssertions

  use ExUnit.Case
  use Patch

  setup do
    start_supervised!({RenameSupervisor, []})
    :ok
  end

  setup do
    pid = self()

    progress_funcs =
      {fn delta, message -> update_progress(pid, delta, message) end,
       fn -> complete_progress(pid) end}

    patch(Proxy, :start_buffering, :ok)
    %{progress_funcs: progress_funcs}
  end

  test "it should mark the `in_progress` as `true` when a rename is in progress.", %{
    progress_funcs: progress_funcs
  } do
    uri = "file://file.ex"
    uri_with_expected_operation = %{uri => file_changed(uri: uri)}
    {:ok, pid} = RenameSupervisor.start_renaming(uri_with_expected_operation, progress_funcs)

    assert Rename.in_progress?()
    assert_called(Proxy.start_buffering(^pid))
  end

  test "it should mark the `in_progress` as false and shutdown the process when a rename is done",
       %{
         progress_funcs: progress_funcs
       } do
    uri = "file://file.ex"

    {:ok, _pid} =
      RenameSupervisor.start_renaming(%{uri => file_saved(uri: uri)}, progress_funcs)

    Rename.update_progress(file_saved(uri: uri))

    assert_receive {:update_progress, 1, ""}
    assert_receive :complete_progress

    refute_eventually Process.whereis(Rename)
  end

  test "it should still in progress if there are files yet to be saved.", %{
    progress_funcs: progress_funcs
  } do
    uri1 = "file://file1.ex"
    uri2 = "file://file2.ex"

    uri_with_expected_operation = %{
      uri1 => file_changed(uri: uri1),
      uri2 => file_saved(uri: uri2)
    }

    {:ok, _pid} = RenameSupervisor.start_renaming(uri_with_expected_operation, progress_funcs)

    Rename.update_progress(file_changed(uri: uri1))
    assert_receive {:update_progress, 1, ""}
    refute_receive :complete_progress
    assert Rename.in_progress?()
  end

  test "it should return `:ok` when updating the progress if the process is not alive" do
    assert :ok = Rename.update_progress(file_changed(uri: "file://file.ex"))
  end

  defp update_progress(pid, delta, message) do
    send(pid, {:update_progress, delta, message})
  end

  defp complete_progress(pid) do
    send(pid, :complete_progress)
  end
end
