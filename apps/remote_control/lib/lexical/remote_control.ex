defmodule Lexical.RemoteControl do
  @moduledoc """
  The remote control boots another elixir application in a separate VM, injects
  the remote control application into it and allows the language server to execute tasks in the
  context of the remote VM.
  """

  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Proxy
  alias Lexical.RemoteControl.CodeAction
  alias Lexical.RemoteControl.CodeIntelligence
  alias Lexical.RemoteControl.ProjectNode

  require Logger

  @excluded_apps [:patch, :nimble_parsec]
  @allowed_apps [:remote_control | Mix.Project.deps_apps()] -- @excluded_apps

  defdelegate schedule_compile(force?), to: Proxy

  defdelegate compile_document(document), to: Proxy

  defdelegate format(document), to: Proxy

  defdelegate reindex, to: Proxy

  defdelegate index_running?, to: Proxy

  defdelegate broadcast(message), to: Proxy

  defdelegate expand_alias(segments_or_module, analysis, position), to: RemoteControl.Analyzer

  defdelegate list_modules, to: :code, as: :all_available

  defdelegate code_actions(document, range, diagnostics, kinds), to: CodeAction, as: :for_range

  defdelegate complete(env), to: RemoteControl.Completion, as: :elixir_sense_expand

  defdelegate complete_struct_fields(analysis, position),
    to: RemoteControl.Completion,
    as: :struct_fields

  defdelegate definition(document, position), to: CodeIntelligence.Definition

  defdelegate references(analysis, position, include_definitions?),
    to: CodeIntelligence.References

  defdelegate modules_with_prefix(prefix), to: RemoteControl.Modules, as: :with_prefix

  defdelegate modules_with_prefix(prefix, predicate), to: RemoteControl.Modules, as: :with_prefix

  defdelegate docs(module, opts \\ []), to: CodeIntelligence.Docs, as: :for_module

  defdelegate register_listener(listener_pid, message_types), to: RemoteControl.Dispatch

  defdelegate resolve_entity(analysis, position), to: CodeIntelligence.Entity, as: :resolve

  defdelegate struct_definitions, to: CodeIntelligence.Structs, as: :for_project

  defdelegate document_symbols(document), to: CodeIntelligence.Symbols, as: :for_document

  defdelegate workspace_symbols(query), to: CodeIntelligence.Symbols, as: :for_workspace

  def start_link(%Project{} = project) do
    :ok = ensure_epmd_started()
    start_net_kernel(project)

    apps_to_start = [:elixir | @allowed_apps] ++ [:runtime_tools]
    node = Project.node_name(project)

    with {:ok, node_pid} <- ProjectNode.start(project, glob_paths()),
         :ok <- ensure_apps_started(node, apps_to_start) do
      {:ok, node, node_pid}
    end
  end

  def deps_paths do
    case :persistent_term.get({__MODULE__, :deps_paths}, :error) do
      :error ->
        {:ok, deps_paths} =
          RemoteControl.Mix.in_project(fn _ ->
            Mix.Task.run("loadpaths")
            Mix.Project.deps_paths()
          end)

        :persistent_term.put({__MODULE__, :deps_paths}, deps_paths)
        deps_paths

      deps_paths ->
        deps_paths
    end
  end

  def with_lock(lock_type, func) do
    :global.trans({lock_type, self()}, func, [Node.self()])
  end

  def project_node? do
    !!:persistent_term.get({__MODULE__, :project}, false)
  end

  def get_project do
    :persistent_term.get({__MODULE__, :project}, nil)
  end

  def set_project(%Project{} = project) do
    :persistent_term.put({__MODULE__, :project}, project)
  end

  defdelegate stop(project), to: ProjectNode

  def call(%Project{} = project, m, f, a \\ []) do
    project
    |> Project.node_name()
    |> :erpc.call(m, f, a)
  end

  def manager_node_name(%Project{} = project) do
    :"manager-#{Project.name(project)}-#{Project.entropy(project)}@127.0.0.1"
  end

  defp start_net_kernel(%Project{} = project) do
    manager = manager_node_name(project)
    :net_kernel.start(manager, %{name_domain: :longnames})
  end

  defp ensure_apps_started(node, app_names) do
    Enum.reduce_while(app_names, :ok, fn app_name, _ ->
      case :rpc.call(node, :application, :ensure_all_started, [app_name]) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp glob_paths do
    for entry <- :code.get_path(),
        entry_string = List.to_string(entry),
        entry_string != ".",
        Enum.any?(app_globs(), &PathGlob.match?(entry_string, &1, match_dot: true)) do
      entry
    end
  end

  defp app_globs do
    app_globs = Enum.map(@allowed_apps, fn app_name -> "/**/#{app_name}*/ebin" end)
    ["/**/priv" | app_globs]
  end

  defp ensure_epmd_started do
    case System.cmd("epmd", ~w(-daemon)) do
      {"", 0} ->
        :ok

      _ ->
        {:error, :epmd_failed}
    end
  end
end
