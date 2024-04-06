defmodule Lexical.RemoteControl.Commands.RenameTest do
  alias Lexical.RemoteControl.Commands.Rename

  use ExUnit.Case
  use Patch

  setup do
    start_supervised!(Rename)
    :ok
  end

  test "it should mark the `in_progress` as `true` when a rename is in progress." do
    assert :ok = Rename.set_rename_progress(%{"file://file.ex" => 3})
    assert Rename.in_progress?()
  end

  test "it should mark the `in_progress` as false when a rename is done" do
    file_uri = "file://file.ex"
    Rename.set_rename_progress(%{file_uri => 3})

    Rename.mark_changed(file_uri)
    Rename.mark_saved(file_uri)
    Rename.mark_closed(file_uri)

    refute Rename.in_progress?()
  end
end
