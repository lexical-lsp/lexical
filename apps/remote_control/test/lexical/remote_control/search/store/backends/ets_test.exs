defmodule Lexical.RemoteControl.Search.Store.Backend.EtsTest do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Store
  alias Lexical.RemoteControl.Search.Store.Backends
  alias Lexical.Test.Entry
  alias Lexical.Test.EventualAssertions
  alias Lexical.Test.Fixtures

  use ExUnit.Case

  import EventualAssertions
  import Entry.Builder
  import Fixtures

  setup do
    backend = Backends.Ets
    project = project()
    # These test cases require an clean slate going into them
    # so we should remove the indexes once when the tests start,
    # and again when tests end, so the next test has a clean slate.
    # Removing the index at the end will also let other test cases
    # start with a clean slate.

    Lexical.RemoteControl.set_project(project)
    delete_indexes(project, backend)

    {:ok, backend: backend, project: project}
  end

  def delete_indexes(project, backend) do
    backend.destroy(project)
  end

  def default_create(_project) do
    {:ok, []}
  end

  def default_update(_project, _entities) do
    {:ok, [], []}
  end

  defp start_supervised_store(%Project{} = project, create_fn, update_fn, backend) do
    start_supervised!({Store, [project, create_fn, update_fn, backend]})
    assert_eventually(ready?(project))
  end

  def with_a_started_store(%{project: project, backend: backend}) do
    start_supervised_store(project, &default_create/1, &default_update/2, backend)

    on_exit(fn ->
      delete_indexes(project, backend)
    end)

    :ok
  end

  describe "starting" do
    test "the create function is called if there are no disk files", %{
      project: project,
      backend: backend
    } do
      me = self()

      create_fn = fn ^project ->
        send(me, :create)
        {:ok, []}
      end

      update_fn = fn _, _ ->
        send(me, :update)
        {:ok, [], []}
      end

      start_supervised!({Store, [project, create_fn, update_fn, backend]})

      assert_eventually(ready?(project))

      assert_receive :create
      refute_receive :update
    end

    test "the start function receives stale if there is a disk file", %{
      project: project,
      backend: backend
    } do
      me = self()

      create_fn = fn ^project -> {:ok, [reference()]} end

      update_fn = fn _, _ ->
        send(me, :update)
        {:ok, [], []}
      end

      start_supervised_store(project, create_fn, update_fn, backend)

      restart_store(project)

      assert_receive :update
    end

    test "starts empty if there are no disk files", %{project: project, backend: backend} do
      start_supervised_store(project, &default_create/1, &default_update/2, backend)

      assert [] = Store.all()

      entry = definition()
      Store.replace([entry])
      assert Store.all() == [entry]
    end

    test "incorporates any indexed files in an empty index", %{project: project, backend: backend} do
      create = fn _ ->
        entries = [
          reference(path: "/foo/bar/baz.ex"),
          reference(path: "/foo/bar/quux.ex")
        ]

        {:ok, entries}
      end

      start_supervised_store(project, create, &default_update/2, backend)

      restart_store(project)

      paths = Enum.map(Store.all(), & &1.path)

      assert "/foo/bar/baz.ex" in paths
      assert "/foo/bar/quux.ex" in paths
    end

    test "fails if the reindex fails on an empty index", %{project: project, backend: backend} do
      create = fn _ -> {:error, :broken} end
      start_supervised_store(project, create, &default_update/2, backend)

      assert_eventually(ready?(project))

      assert Store.all() == []
    end

    test "incorporates any indexed files in a stale index", %{project: project, backend: backend} do
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

      start_supervised_store(project, create, update, backend)

      restart_store(project)

      entries = Enum.map(Store.all(), &{&1.ref, &1.path})
      assert {2, "/foo/bar/quux.ex"} in entries
      assert {3, "/foo/bar/baz.ex"} in entries
      assert {4, "/foo/bar/other.ex"} in entries
    end

    test "fails if the reinder fails on an stale index", %{project: project, backend: backend} do
      create = fn _ -> {:ok, []} end
      update = fn _, _ -> {:error, :bad} end

      start_supervised_store(project, create, update, backend)
      restart_store(project)

      assert [] = Store.all()
    end

    test "the updater allows you to delete paths", %{project: project, backend: backend} do
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

      start_supervised_store(project, create, update, backend)

      restart_store(project)

      assert [entry] = Store.all()
      assert entry.path == "/path/to/keep.ex"
    end
  end

  describe "replace/1" do
    setup [:with_a_started_store]

    test "replace survives a restart", %{project: project} do
      entries = [definition(subject: My.Module)]

      assert :ok = Store.replace(entries)

      Backends.Ets.force_sync(project)
      Store.stop()

      refute_eventually(ready?(project))
      assert_eventually(ready?(project))

      assert entries == Store.all()
    end
  end

  describe "updating entries in a file" do
    setup [:with_a_started_store]

    test "updates survive a restart", %{project: project} do
      path = "/path/to/something.ex"
      Store.replace([definition(ref: 1, subject: My.Module, path: path)])

      Store.update(path, [
        reference(ref: 2, subject: Present, path: path)
      ])

      Backends.Ets.force_sync(project)
      Store.stop()

      refute_eventually(ready?(project))
      assert_eventually(ready?(project))

      assert [found] = Store.all()
      assert found.ref == 2
    end
  end

  def restart_store(%Project{} = project) do
    Backends.Ets.force_sync(project)

    Store
    |> Process.whereis()
    |> Process.monitor()

    Store.stop()
    refute_eventually(ready?(project))

    receive do
      {:DOWN, _, _, _, _} ->
        assert_eventually(ready?(project))
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

  def ready?(%Project{} = project) do
    alive?() and registered?(project) and Store.loaded?()
  end

  def registered?(%Project{} = project) do
    case :global.whereis_name({:ets_search, Project.name(project)}) do
      :undefined ->
        false

      _pid ->
        true
    end
  end
end
