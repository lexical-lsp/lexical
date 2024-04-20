defmodule Lexical.RemoteControl.Commands.RenameTest do
  alias Lexical.RemoteControl.Commands.Rename

  defmodule FakeDidChange do
    defstruct [:field]
  end

  defmodule FakeDidSave do
    defstruct [:field]
  end

  use ExUnit.Case
  use Patch

  setup do
    start_supervised!(Rename)
    :ok
  end

  test "it should mark the `in_progress` as `true` when a rename is in progress." do
    assert :ok = Rename.set_rename_progress(%{"file://file.ex" => FakeDidChange})
    assert Rename.in_progress?()
  end

  test "it should mark the `in_progress` as false when a rename is done" do
    file_uri = "file://file.ex"
    Rename.set_rename_progress(%{file_uri => FakeDidSave})
    Rename.update_progress(file_uri, %FakeDidSave{})

    refute Rename.in_progress?()
  end

  test "it should still in progress if there are files yet to be saved." do
    uri1 = "file://file1.ex"
    uri2 = "file://file2.ex"

    Rename.set_rename_progress(%{uri1 => FakeDidChange, uri2 => FakeDidSave})
    Rename.update_progress(uri1, %FakeDidChange{})

    assert Rename.in_progress?()
  end
end
