defmodule Lexical.RemoteControl do
  @moduledoc """
  The remote control boots another elixir application in a separate VM, injects
  the remote control application into it and allows the language server to execute tasks in the
  context of the remote VM.
  """

  alias Lexical.Project
  alias Lexical.RemoteControl

  @allowed_apps ~w(common path_glob remote_control elixir_sense)a

  @app_globs Enum.map(@allowed_apps, fn app_name -> "/**/#{app_name}*/ebin" end)

  @localhost_string "127.0.0.1"

  def start_link(%Project{} = project, project_listener) do
    entropy = :rand.uniform(65536)

    start_net_kernel(entropy)

    node_name = String.to_charlist("#{Project.name(project)}")
    {:ok, paths} = system_paths(project)

    erl_args =
      erl_args([
        "-hosts #{@localhost_string}",
        "-setcookie #{Node.get_cookie()}",
        "-sbwt none",
        "-path #{paths}",
        "-noshell"
      ])

    apps_to_start = [:elixir | @allowed_apps] ++ [:runtime_tools]

    with {:ok, node} <-
           :slave.start_link(String.to_charlist(@localhost_string), node_name, erl_args),
         :ok <- :rpc.call(node, :code, :add_paths, [glob_paths()]),
         :ok <- :rpc.call(node, RemoteControl.Bootstrap, :init, [project]),
         :ok <- :rpc.call(node, __MODULE__, :set_project, [project]),
         :ok <- :rpc.call(node, __MODULE__, :set_project_listener_pid, [project_listener]),
         :ok <- :rpc.call(node, File, :cd, [Project.root_path(project)]),
         :ok <- ensure_apps_started(node, apps_to_start) do
      {:ok, node}
    end
  end

  def with_lock(lock_type, func) do
    :global.trans({lock_type, self()}, func)
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
    project
    |> node_name()
    |> :slave.stop()
  end

  def call(%Project{} = project, m, f, a \\ []) do
    project
    |> node_name()
    |> :erpc.call(m, f, a)
  end

  defp node_name(%Project{} = project) do
    :"#{Project.name(project)}@127.0.0.1"
  end

  defp start_net_kernel(entropy) do
    :net_kernel.start([:"manager-#{entropy}@127.0.0.1"])
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

  defp erl_args(arg_list) do
    arg_list
    |> Enum.join(" ")
    |> String.to_charlist()
  end

  def system_paths(%Project{} = project) do
    old_cwd = File.cwd!()
    root_path = Project.root_path(project)

    result =
      with :ok <- File.cd(root_path),
           {:ok, elixir} <- elixir_executable(),
           {:ok, paths} <- elixir_code_paths(elixir) do
        {:ok, format_paths(paths)}
      end

    File.cd(old_cwd)
    result
  end

  defp elixir_executable do
    case System.find_executable("elixir") do
      nil -> {:error, :no_elixir}
      executable -> {:ok, executable}
    end
  end

  def format_paths(paths_as_charlists) do
    Enum.map_join(paths_as_charlists, " ", &Path.expand/1)
  end

  defp elixir_code_paths(elixir_executable) do
    with {output, 0} <- System.cmd(elixir_executable, ~w[--eval IO.inspect(:code.get_path())]),
         {evaluated, _} <- Code.eval_string(output) do
      {:ok, evaluated}
    end
  end
end
