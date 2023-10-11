alias Lexical.Project
alias Lexical.RemoteControl
alias Lexical.RemoteControl.Search.Store.Backends.Ets
alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schema
alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas

defmodule BenchHelper do
  def wait_for_registration do
    case :global.registered_names() do
      [] ->
        Process.sleep(100)
        wait_for_registration()

      _ ->
        :ok
    end
  end

  def random_path(entries) do
    Enum.random(entries).path
  end

  def random_ref(entries) do
    Enum.random(entries).ref
  end

  def random_refs(entries, count) do
    entries
    |> Enum.take_random(count)
    |> Enum.map(& &1.ref)
  end
end

cwd = __DIR__
project = Project.new("file://#{cwd}")

RemoteControl.set_project(project)
Project.ensure_workspace(project)

indexes_path = Project.workspace_path(project, "indexes")
data_dir = Path.join(cwd, "data")

File.mkdir_p!(indexes_path)
File.cp_r!(data_dir, indexes_path)

{:ok, ets} = Ets.start_link(project)

BenchHelper.wait_for_registration()
Ets.prepare(ets)

entries = Ets.select_all()

Benchee.run(
  %{
    "find_by_subject" => fn _ ->
      Ets.find_by_subject(Enum, :module, :reference)
    end,
    "find_by_subject, type_wildcard" => fn _ ->
      Ets.find_by_subject(Enum, :_, :reference)
    end,
    "find_by_subject, subtype_wildcard" => fn _ ->
      Ets.find_by_subject(Enum, :module, :_)
    end,
    "find_by_subject, two wildcards" => fn _ ->
      Ets.find_by_subject(Enum, :_, :_)
    end,
    "find_by_references" => fn %{refs: refs} ->
      Ets.find_by_refs(refs, :module, :_)
    end,
    "delete_by_path" => fn %{path: path} ->
      Ets.delete_by_path(path)
    end
  },
  before_each: fn _ ->
    refs = BenchHelper.random_refs(entries, 50)
    path = BenchHelper.random_path(entries)
    %{path: path, refs: refs}
  end
)

File.rm_rf(Project.workspace_path(project))
