defmodule Lexical.RemoteControl.Search.StoreTest do
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store

  use ExUnit.Case
  use Patch

  import Lexical.Test.EventualAssertions
  import Lexical.Test.Entry.Builder
  import Lexical.Test.Fixtures

  setup do
    expose(Entry, tokenize: 1)
    project = project()
    start_supervised!({Store, [project, fn -> {:ok, []} end]})

    on_exit(fn ->
      project
      |> Store.State.index_path()
      |> File.rm()
    end)

    {:ok, project: project}
  end

  test "it has a schema" do
    assert %{schema_version: 1} = Store.schema()
  end

  test "the schema survives restarts" do
    assert %{schema_version: 1} = Store.schema()

    restart_store()

    assert %{schema_version: 1} = Store.schema()
  end

  describe "starting" do
    test "starts empty if there are no disk files" do
      assert [] = Store.all()

      entry = definition()
      Store.replace([entry])
      assert Store.all() == [entry]
    end
  end

  describe "replace/1" do
    test "replaces the entire index" do
      entries = [definition(subject: OtherModule)]

      Store.replace(entries)
      assert entries == Store.all()
    end

    test "replace survives a restart" do
      entries = [definition(subject: My.Module)]

      assert :ok = Store.replace(entries)

      restart_store()

      assert entries == Store.all()
    end
  end

  describe "querying" do
    test "matching can exclude on type" do
      Store.replace([
        definition(ref: 1),
        reference(ref: 3)
      ])

      assert {:ok, [ref]} = Store.exact(subtype: :reference)
      assert ref.subtype == :reference
    end

    test "matching can exclude on elixir version" do
      Store.replace([
        reference(subject: Enum, elixir_version: "1.0.0"),
        reference(subject: Enum)
      ])

      assert {:ok, [ref]} = Store.exact("Enum", subtype: :reference)
      assert ref.subject == Enum
      refute ref.elixir_version == "1.0.0"
    end

    test "matching can exclude on erlang version" do
      Store.replace([
        reference(subject: Enum, erlang_version: "1.0.0"),
        reference(subject: Enum)
      ])

      assert {:ok, [ref]} = Store.exact("Enum", subtype: :reference)

      assert ref.subject == Enum
      refute ref.erlang_version == "1.0.0"
    end

    test "matching with queries can exclude on type" do
      Store.replace([
        reference(subject: Foo.Bar.Baz),
        reference(subject: Other.Module),
        definition(subject: Foo.Bar.Baz)
      ])

      assert {:ok, [ref]} = Store.exact("Foo.Bar.Baz", subtype: :reference)

      assert ref.subject == Foo.Bar.Baz
      assert ref.type == :module
      assert ref.subtype == :reference
    end

    test "matching exact tokens should work" do
      Store.replace([
        definition(ref: 1, subject: Foo.Bar.Baz),
        definition(ref: 2, subject: Foo.Bar.Bak)
      ])

      assert {:ok, [entry]} = Store.exact("Foo.Bar.Baz", type: :module, subtype: :definition)

      assert entry.subject == Foo.Bar.Baz
      assert entry.ref == 1
    end

    test "matching fuzzy tokens works" do
      Store.replace([
        definition(ref: 1, subject: Foo.Bar.Baz),
        definition(ref: 2, subject: Foo.Bar.Bak),
        definition(ref: 3, subject: Bad.Times.Now)
      ])

      assert {:ok, [entry_1, entry_2]} =
               Store.fuzzy("Foo.Bar.B", type: :module, subtype: :definition)

      assert entry_1.subject in [Foo.Bar.Baz, Foo.Bar.Bak]
      assert entry_2.subject in [Foo.Bar.Baz, Foo.Bar.Bak]
    end
  end

  describe "updating entries in a file" do
    test "old entries with the same path are deleted" do
      path = "/path/to/file.ex"

      Store.replace([
        definition(ref: 1, subject: Foo.Bar.Baz, path: path),
        definition(ref: 2, subject: Foo.Baz.Quux, path: path)
      ])

      updated = [
        definition(ref: 3, subject: Other.Thing.Entirely, path: path)
      ]

      Store.update(path, updated)

      assert [remaining] = Store.all()
      refute remaining.ref in [1, 2]
    end

    test "old entries with another path are kept" do
      updated_path = "/path/to/file.ex"

      Store.replace([
        definition(ref: 1, subject: Foo.Bar.Baz, path: updated_path),
        definition(ref: 2, subject: Foo.Bar.Baz.Quus, path: updated_path),
        definition(ref: 3, subject: Foo.Bar.Baz, path: "/path/to/another.ex")
      ])

      updated = [
        definition(ref: 4, subject: Other.Thing.Entirely, path: updated_path)
      ]

      Store.update(updated_path, updated)

      assert [first, second] = Store.all()

      assert first.ref in [3, 4]
      assert second.ref in [3, 4]
    end

    test "updated entries are not searchable" do
      path = "/path/to/ex.ex"

      Store.replace([
        reference(ref: 1, subject: Should.Be.Replaced, path: path)
      ])

      Store.update(path, [
        reference(ref: 2, subject: Present, path: path)
      ])

      assert {:ok, [found]} = Store.fuzzy("Pres", type: :module, subtype: :reference)
      assert found.ref == 2
      assert found.subject == Present
    end

    test "updates survive a restart" do
      path = "/path/to/something.ex"
      Store.replace([definition(ref: 1, subject: My.Module, path: path)])

      Store.update(path, [
        reference(ref: 2, subject: Present, path: path)
      ])

      Store.stop()

      assert_eventually alive?()
      assert [found] = Store.all()
      assert found.ref == 2
    end
  end

  def restart_store do
    Store
    |> Process.whereis()
    |> Process.monitor()

    Store.stop()

    receive do
      {:DOWN, _, _, _, _} ->
        assert_eventually alive?()
    after
      1000 ->
        raise "Could not stop store"
    end
  end

  def alive? do
    case Process.whereis(Store) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end
end
