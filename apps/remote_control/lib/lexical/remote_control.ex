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
    remote_control_config = Application.get_all_env(:remote_control)

    node = node_name(project)
    paths = format_prepending_paths(glob_paths())
    start_options = [paths: paths, name: Atom.to_string(node), cookie: Node.get_cookie()]

    with {:ok, _} <- ProjectNode.start_link(start_options),
         :ok <- wait_until_connected(node),
         :ok <-
           :rpc.call(node, RemoteControl.Bootstrap, :init, [
             project,
             project_listener,
             remote_control_config
           ]),
         :ok <- ensure_apps_started(node, apps_to_start) do
      supervisor_pid = :rpc.call(node, Process, :whereis, [Lexical.RemoteControl.Supervisor])
      {:ok, node, supervisor_pid}
    end
  end

  def wait_until_connected(node, timeout \\ 5_000)

  def wait_until_connected(_node, timeout) when timeout <= 0 do
    {:error, :timeout}
  end

  def wait_until_connected(node, timeout) do
    if Node.connect(node) do
      :ok
    else
      Process.sleep(200)
      wait_until_connected(node, timeout - 200)
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

  def stop(%Project{} = project) do
    node = node_name(project)
    :ok = :rpc.call(node, :init, :stop, [])
    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)

    receive do
      {:nodedown, ^node, _} ->
        :ok
    after
      5_000 ->
        Logger.warn("Node #{inspect(node)} did not go down after 5 seconds")
        {:error, :timeout}
    end
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

  def system_paths(%Project{} = project) do
    old_cwd = File.cwd!()
    root_path = Project.root_path(project)

    result =
      with :ok <- File.cd(root_path),
           {:ok, elixir} <- elixir_executable(project),
           {:ok, paths} <- elixir_code_paths(project, elixir) do
        {:ok, format_prepending_paths(paths)}
      end

    File.cd(old_cwd)
    result
  end

  defp elixir_executable(%Project{} = project) do
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

  defp format_prepending_paths(paths_as_charlists) do
    Enum.map_join(paths_as_charlists, " -pa ", &Path.expand/1)
  end

  defp elixir_code_paths(%Project{} = project, elixir_executable) do
    root_path = Project.root_path(project)
    command = ~w[--eval IO.inspect(:code.get_path())]

    with {output, 0} <- System.cmd(elixir_executable, command, cd: root_path),
         {evaluated, _} <- Code.eval_string(output) do
      {:ok, evaluated}
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
