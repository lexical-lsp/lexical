defmodule Lexical.RemoteControl.Commands.RenameTest do
  alias Lexical.RemoteControl.Commands.Rename

  import Lexical.RemoteControl.Api.Messages

  use ExUnit.Case
  use Patch

  setup do
    start_supervised!(Rename)
    pid = self()

    progress_funcs =
      {fn delta, message -> update_progress(pid, delta, message) end,
       fn -> complete_progress(pid) end}

    %{progress_funcs: progress_funcs}
  end

  test "it should mark the `in_progress` as `true` when a rename is in progress.", %{
    progress_funcs: progress_funcs
  } do
    uri = "file://file.ex"
    assert :ok = Rename.set_rename_progress(%{uri => file_changed(uri: uri)}, progress_funcs)
    assert Rename.in_progress?()
  end

  test "it should mark the `in_progress` as false when a rename is done", %{
    progress_funcs: progress_funcs
  } do
    file_uri = "file://file.ex"

    Rename.set_rename_progress(%{file_uri => file_saved(uri: file_uri)}, progress_funcs)
    Rename.update_progress(file_saved(uri: file_uri))

    assert_receive {:update_progress, 1, ""}
    assert_receive :complete_progress

    refute Rename.in_progress?()
  end

  test "it should still in progress if there are files yet to be saved.", %{
    progress_funcs: progress_funcs
  } do
    uri1 = "file://file1.ex"
    uri2 = "file://file2.ex"

    Rename.set_rename_progress(
      %{uri1 => file_changed(uri: uri1), uri2 => file_saved(uri: uri2)},
      progress_funcs
    )

    Rename.update_progress(file_changed(uri: uri1))

    assert_receive {:update_progress, 1, ""}

    refute_receive :complete_progress
    assert Rename.in_progress?()
  end

  defp update_progress(pid, delta, message) do
    send(pid, {:update_progress, delta, message})
  end

  defp complete_progress(pid) do
    send(pid, :complete_progress)
  end
end
