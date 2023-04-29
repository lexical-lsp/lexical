defmodule Lexical.RemoteControl do
  @moduledoc """
  The remote control boots another elixir application in a separate VM, injects
  the remote control application into it and allows the language server to execute tasks in the
  context of the remote VM.
  """

  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.ProjectNode
  require Logger

  @allowed_apps ~w(common path_glob remote_control elixir_sense)a

  @app_globs Enum.map(@allowed_apps, fn app_name -> "/**/#{app_name}*/ebin" end)

  def start_link(%Project{} = project, project_listener) do
    :ok = ensure_epmd_started()
    entropy = :rand.uniform(65_536)
    start_net_kernel(project, entropy)

    apps_to_start = [:elixir | @allowed_apps] ++ [:runtime_tools]
    node = node_name(project)

    with {:ok, _} <- ProjectNode.start(project, project_listener),
         :ok <- ensure_apps_started(node, apps_to_start) do
      supervisor_pid = :rpc.call(node, Process, :whereis, [RemoteControl.Supervisor])
      {:ok, node, supervisor_pid}
    end
  end

  def with_lock(lock_type, func) do
    :global.trans({lock_type, self()}, func, [Node.self()])
  end

  def notify_listener(message) do
    send(project_listener_pid(), message)
  end

  def project_node? do
    !!:persistent_term.get({__MODULE__, :project}, false)
  end

  def get_project do
    :persistent_term.get({__MODULE__, :project})
  end

  def project_listener_pid do
    :persistent_term.get({__MODULE__, :project_listener_pid})
  end

  def set_project_listener_pid(listener_pid) do
    :persistent_term.put({__MODULE__, :project_listener_pid}, listener_pid)
  end

  def set_project(%Project{} = project) do
    :persistent_term.put({__MODULE__, :project}, project)
  end

  def stop(%Project{} = project, stop_timeout \\ 1_000) do
    ProjectNode.stop(project, stop_timeout)
  end

  def call(%Project{} = project, m, f, a \\ []) do
    project
    |> node_name()
    |> :erpc.call(m, f, a)
  end

  defp node_name(%Project{} = project) do
    :"#{Project.name(project)}@127.0.0.1"
  end

  defp start_net_kernel(%Project{} = project, entropy) do
    :net_kernel.start([:"manager-#{Project.name(project)}-#{entropy}@127.0.0.1"])
  end

  def ensure_apps_started(node, app_names) do
    Enum.reduce_while(app_names, :ok, fn app_name, _ ->
      case :rpc.call(node, :application, :ensure_all_started, [app_name]) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def glob_paths do
    for entry <- :code.get_path(),
        entry_string = List.to_string(entry),
        entry_string != ".",
        Enum.any?(@app_globs, &PathGlob.match?(entry_string, &1, match_dot: true)) do
      entry
    end
  end

  def elixir_executable(%Project{} = project) do
    root_path = Project.root_path(project)

    path_result =
      case version_manager() do
        :asdf ->
          case System.cmd("asdf", ~w(which elixir), cd: root_path) do
            {path, 0} ->
              String.trim(path)

            _ ->
              nil
          end

        :rtx ->
          case System.cmd("rtx", ~w(which elixir), cd: root_path) do
            {path, 0} ->
              String.trim(path)

            _ ->
              nil
          end

        :none ->
          File.cd!(root_path, fn -> System.find_executable("elixir") end)
      end

    case path_result do
      nil ->
        {:error, :no_elixir}

      executable when is_binary(executable) ->
        {:ok, executable}
    end
  end

  defp ensure_epmd_started do
    case System.cmd("epmd", ~w(-daemon)) do
      {"", 0} ->
        :ok

      _ ->
        {:error, :epmd_failed}
    end
  end

  defp version_manager do
    cond do
      asdf?() ->
        :asdf

      rtx?() ->
        :rtx

      true ->
        :none
    end
  end

  defp asdf?, do: is_binary(System.find_executable("asdf"))

  defp rtx?, do: is_binary(System.find_executable("rtx"))
end
