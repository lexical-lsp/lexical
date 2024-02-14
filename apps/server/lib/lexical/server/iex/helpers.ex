defmodule Lexical.Server.IEx.Helpers do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search
  alias Lexical.Server.CodeIntelligence

  defmacro __using__(_) do
    quote do
      alias Lexical.Document
      alias Lexical.Document.Position
      alias Lexical.RemoteControl
      alias Lexical.RemoteControl.Search
      import unquote(__MODULE__)

      RemoteControl.Module.Loader.start_link(nil)
      RemoteControl.Dispatch.start_link([])
    end
  end

  def observer do
    # credo:disable-for-next-line
    apply(:observer, :start, [])
  end

  def observer(project) do
    project
    |> ensure_project()
    |> RemoteControl.call(:observer, :start)
  end

  def doc(text) do
    doc(:lexical, text)
  end

  def project_node(name) do
    name
    |> project()
    |> Project.node_name()
  end

  def doc(project, text) do
    root_path =
      project
      |> project()
      |> Project.root_path()

    [root_path, "lib", "file.ex"]
    |> Path.join()
    |> Document.Path.to_uri()
    |> Document.new(text, 0)
  end

  def search_store(project) do
    project = ensure_project(project)
    RemoteControl.set_project(project)

    Search.Store.start_link(
      project,
      &Search.Indexer.create_index/1,
      &Search.Indexer.update_index/2,
      Search.Store.Backends.Ets
    )
  end

  def search_entries(project) do
    {:ok, entries} =
      project
      |> ensure_project()
      |> Search.Indexer.create_index()

    entries
  end

  def pos(doc, line, character) do
    Position.new(doc, line, character)
  end

  def compile_project(project) do
    project
    |> ensure_project()
    |> RemoteControl.Api.schedule_compile(true)
  end

  def compile_file(project, source) when is_binary(source) do
    project
    |> ensure_project()
    |> compile_file(doc(source))
  end

  def compile_file(project, %Document{} = document) do
    project
    |> ensure_project()
    |> RemoteControl.Api.compile_document(document)
  end

  def complete(project, source, context \\ nil)

  def complete(project, source, context) when is_binary(source) do
    case completion_position(source) do
      {:found, line, character} ->
        analysis = source |> doc() |> Ast.analyze()
        complete(project, analysis, line, character, context)

      other ->
        other
    end
  end

  def complete(project, %Ast.Analysis{} = analysis, line, character, context) do
    context =
      if is_nil(context) do
        Completion.Context.new(trigger_kind: :trigger_character)
      else
        context
      end

    position = pos(analysis.document, line, character)

    project
    |> ensure_project()
    |> CodeIntelligence.Completion.complete(analysis, position, context)
  end

  def connect do
    manager_name = manager_name()
    Node.start(:"r@127.0.0.1")
    Node.set_cookie(:lexical)
    Node.connect(:"#{manager_name}@127.0.0.1")
  end

  @doc """
  Create a Lexical Project for an application in the same directory as
  Lexical.

  Alternatively, a project for one of our test fixtures can be created
  using the `fixture: true` option.

  ## Examples

      iex> project()
      %Lexical.Project{
        root_uri: "file:///.../lexical
        ...
      }

      iex> project(:my_project)
      %Lexical.Project{
        root_uri: "file:///.../my_project"
        ...
      }

      iex> project(:navigations, fixture: true)
      %Lexical.Project{
        root_uri: "file:///.../lexical/apps/remote_control/test/fixtures/navigations"
        ...
      }

  """
  def project(project \\ :lexical, opts \\ []) do
    project =
      if opts[:fixture] do
        "lexical/apps/remote_control/test/fixtures/#{project}"
      else
        project
      end

    # We're using a cache here because we need project's
    # entropy to be the same after every call.
    trans(project, fn ->
      project_path =
        [File.cwd!(), "..", to_string(project)]
        |> Path.join()
        |> Path.expand()

      project_uri = "file://#{project_path}"
      Lexical.Project.new(project_uri)
    end)
  end

  def current_project do
    [prefix, _] = Node.self() |> to_string() |> String.split("@")
    [_, project_name, entropy] = String.split(prefix, "-")
    %{ensure_project(project_name) | entropy: entropy}
  end

  def stop_project(project) do
    project
    |> ensure_project()
    |> Lexical.Server.Project.Supervisor.stop()
  end

  def start_project(project) do
    project
    |> ensure_project()
    |> Lexical.Server.Project.Supervisor.start()
  end

  def time(fun) when is_function(fun, 0) do
    {elapsed_us, result} = :timer.tc(fun)

    IO.puts([
      IO.ANSI.format([:cyan, :bright, "Time: "]),
      Lexical.Formats.time(elapsed_us)
    ])

    result
  end

  defp manager_name do
    {:ok, names} = :erl_epmd.names()

    names
    |> Enum.map(fn {name, _port} -> List.to_string(name) end)
    |> Enum.find(&String.starts_with?(&1, "manager"))
  end

  defp completion_position(source_string) do
    source_string
    |> String.split(["\r\n", "\r", "\n"])
    |> Enum.with_index()
    |> Enum.reduce_while(:not_found, fn {line, line_number}, _ ->
      if String.contains?(line, "|") do
        index =
          line
          |> String.graphemes()
          |> Enum.find_index(&(&1 == "|"))

        {:halt, {:found, line_number + 1, index + 1}}
      else
        {:cont, :not_found}
      end
    end)
  end

  defp ensure_project(%Project{} = project) do
    project
  end

  defp ensure_project(project) when is_binary(project) do
    project
    |> String.to_atom()
    |> project()
  end

  defp ensure_project(project) when is_atom(project) do
    project(project)
  end

  defp trans(name, function) do
    name = {__MODULE__, name}

    case :persistent_term.get(name, :undefined) do
      :undefined ->
        value = function.()
        :persistent_term.put(name, value)

      _ ->
        :ok
    end

    :persistent_term.get(name)
  end
end
