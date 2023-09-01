defmodule Lexical.RemoteControl.Search.StoreTest do
  alias Lexical.RemoteControl.Search.Store
  alias Lexical.Test.Entry
  alias Lexical.Test.EventualAssertions
  alias Lexical.Test.Fixtures

  use ExUnit.Case

  import EventualAssertions
  import Entry.Builder
  import Fixtures

  setup do
    project = project()

    on_exit(fn ->
      project
      |> Store.State.index_path()
      |> File.rm()
    end)

    {:ok, project: project}
  end

  def default_create(_project) do
    {:ok, []}
  end

  def default_update(_project, _entities) do
    {:ok, [], []}
  end

  def with_a_started_store(%{project: project}) do
    create_index = fn _ -> {:ok, []} end
    update_index = fn _ -> {:ok, [], []} end

    start_supervised!({Store, [project, create_index, update_index]})

    on_exit(fn ->
      project
      |> Store.State.index_path()
      |> File.rm()
    end)

    :ok
  end

  describe "starting" do
    test "the create function is called if there are no disk files", %{project: project} do
      me = self()

      create_fn = fn ^project ->
        send(me, :create)
        {:ok, []}
      end

      update_fn = fn _ ->
        send(me, :update)
        {:ok, [], []}
      end

      start_supervised!({Store, [project, create_fn, update_fn]})

      assert_receive :create
      refute_receive :update
    end

    test "the start function receives stale if there is a disk file", %{project: project} do
      me = self()
      create_fn = fn ^project -> {:ok, []} end

      update_fn = fn _, _ ->
        send(me, :update)
        {:ok, [], []}
      end

      start_supervised!({Store, [project, create_fn, update_fn]})
      restart_store()

      assert_receive :update
    end

    test "starts empty if there are no disk files", %{project: project} do
      Store.start_link([project, &default_create/1, &default_update/2])
      assert [] = Store.all()

      entry = definition()
      Store.replace([entry])
      assert Store.all() == [entry]
    end

    test "incorporates any indexed files in an empty index", %{project: project} do
      create = fn _ ->
        entries = [
          reference(path: "/foo/bar/baz.ex"),
          reference(path: "/foo/bar/quux.ex")
        ]

        {:ok, entries}
      end

      start_supervised!({Store, [project, create, &default_update/2]})
      restart_store()
      paths = Enum.map(Store.all(), & &1.path)

      assert "/foo/bar/baz.ex" in paths
      assert "/foo/bar/quux.ex" in paths
    end

    test "fails if the reindex fails on an empty index", %{project: project} do
      create = fn _ -> {:error, :broken} end
      start_supervised!({Store, [project, create, &default_update/2]})
      assert Store.all() == []
    end

    test "incorporates any indexed files in a stale index", %{project: project} do
      create = fn
        _ ->
          {:ok,
           [
             reference(ref: 1, path: "/foo/bar/baz.ex"),
             reference(ref: 2, path: "/foo/bar/quux.ex")
           ]}
      end

      update = fn _, _ ->
        entries = [
          reference(ref: 3, path: "/foo/bar/baz.ex"),
          reference(ref: 4, path: "/foo/bar/other.ex")
        ]

        {:ok, entries, []}
      end

      start_supervised!({Store, [project, create, update]})
      restart_store()

      entries = Enum.map(Store.all(), &{&1.ref, &1.path})
      assert {2, "/foo/bar/quux.ex"} in entries
      assert {3, "/foo/bar/baz.ex"} in entries
      assert {4, "/foo/bar/other.ex"} in entries
    end

    test "fails if the reinder fails on an stale index", %{project: project} do
      create = fn _ -> {:ok, []} end
      update = fn _, _ -> {:error, :bad} end

      start_supervised!({Store, [project, create, update]})
      restart_store()

      assert [] = Store.all()
    end

    test "the updater allows you to delete paths", %{project: project} do
      create = fn _ ->
        entries = [
          definition(path: "/path/to/keep.ex"),
          definition(path: "/path/to/delete.ex"),
          definition(path: "/path/to/delete.ex"),
          definition(path: "/another/path/to/delete.ex")
        ]

        {:ok, entries}
      end

      update = fn _, _ ->
        {:ok, [], ["/path/to/delete.ex", "/another/path/to/delete.ex"]}
      end

      start_supervised!({Store, [project, create, update]})
      restart_store()
      assert [entry] = Store.all()
      assert entry.path == "/path/to/keep.ex"
    end
  end

  describe "metadata" do
    setup [:with_a_started_store]

    test "it has table metadata" do
      assert metadata = Store.metadata()
      assert metadata.schema_version == 1
      assert metadata.types == [:module]
      assert metadata.subtypes == [:definition, :reference]
    end

    test "the schema survives restarts" do
      assert %{schema_version: 1} = Store.metadata()

      restart_store()

      assert %{schema_version: 1} = Store.metadata()
    end
  end

  describe "replace/1" do
    setup [:with_a_started_store]

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
    setup [:with_a_started_store]

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

    test "matching only returns entries specific to our elixir version" do
      Store.replace([
        definition(ref: 1, subject: Foo.Bar.Baz, elixir_version: "1.1"),
        definition(ref: 2, subject: Foo.Bar.Baz)
      ])

      assert {:ok, [entry]} = Store.fuzzy("Foo.Bar.", type: :module, subtype: :definition)
      assert entry.ref == 2
    end

    test "matching only returns entries specific to our erlang version" do
      Store.replace([
        definition(ref: 1, subject: Foo.Bar.Baz, erlang_version: "14.3.2.8"),
        definition(ref: 2, subject: Foo.Bar.Baz)
      ])

      assert {:ok, [entry]} = Store.fuzzy("Foo.Bar.", type: :module, subtype: :definition)
      assert entry.ref == 2
    end
  end

  describe "unique_fields/1" do
    setup [:with_a_started_store]

    test "should return paths" do
      Store.replace([
        definition(ref: 1, path: "/foo/bar/baz.ex"),
        reference(ref: 2, path: "/foo/bar/quux.ex"),
        definition(ref: 3, path: "/foo/bar/other.ex")
      ])

      paths = Store.unique_fields([:path])

      assert length(paths) == 3
      assert %{path: "/foo/bar/baz.ex"} in paths
      assert %{path: "/foo/bar/quux.ex"} in paths
      assert %{path: "/foo/bar/other.ex"} in paths
    end

    test "should filter this elixir version" do
      Store.replace([
        definition(ref: 1, path: "/foo/bar/baz.ex"),
        definition(ref: 1, path: "/foo/bar/baz/old.ex", elixir_version: "0.13.0")
      ])

      assert [%{path: "/foo/bar/baz.ex"}] = Store.unique_fields([:path])
    end

    test "should filter this erlang version" do
      Store.replace([
        definition(ref: 1, path: "/foo/bar/baz.ex"),
        definition(ref: 1, path: "/foo/bar/baz/old.ex", erlang_version: "18.0.0")
      ])

      assert [%{path: "/foo/bar/baz.ex"}] = Store.unique_fields([:path])
    end
  end

  describe "updating entries in a file" do
    setup [:with_a_started_store]

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
