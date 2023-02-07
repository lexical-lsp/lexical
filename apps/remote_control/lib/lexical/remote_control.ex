defmodule Lexical.RemoteControl do
  @moduledoc """
  The remote control boots another elixir application in a separate VM, injects
  the remote control application into it and allows the language server to execute tasks in the
  context of the remote VM.
  """

  alias Lexical.Project

  @allowed_apps ~w(mix logger common path_glob remote_control elixir_sense)a
  @system_globs [
    "/**/erlang/**/ebin",
    "/**/elixir*/ebin",
    "/**/hex*/ebin"
  ]

  @app_globs Enum.map(@allowed_apps, fn app_name -> "/**/#{app_name}*/ebin" end)
  @allow_globs Enum.concat(@system_globs, @app_globs)

  @localhost_ip {0, 0, 0, 0}
  @localhost_string '127.0.0.1'

  def start_link(%Project{} = project, project_listener) do
    entropy = :rand.uniform(65536)

    ensure_started(entropy)

    node_name = String.to_charlist("#{Project.name(project)}")

    erl_args =
      erl_args([
        "-loader inet",
        "-hosts 127.0.0.1",
        "-setcookie #{Node.get_cookie()}",
        "-sbwt none",
        "-noshell"
      ])

    apps_to_start = [:elixir | @allowed_apps] ++ [:runtime_tools]

    with {:ok, node} <- :slave.start_link('127.0.0.1', node_name, erl_args),
         :ok <- :rpc.call(node, :code, :add_paths, [glob_paths()]),
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

  defp ensure_started(entropy) do
    # boot server startup
    start_boot_server = fn ->
      # voodoo flag to generate a "started" atom flag
      once("boot_server:started", fn ->
        {:ok, _} = :erl_boot_server.start([@localhost_ip, {127, 0, 0, 1}])
      end)

      :ok
    end

    # only ever handle the :erl_boot_server on the initial startup
    case :net_kernel.start([:"manager-#{entropy}@127.0.0.1"]) do
      # handle nodes that have already been started elsewhere
      {:error, {{:already_started, _}, _}} -> start_boot_server.()
      {:error, {:already_started, _}} -> start_boot_server.()
      # handle the node being started
      {:ok, _} -> start_boot_server.()
      # pass anything else
      anything -> anything
    end
  end

  defp once(flag, func) do
    with_lock(flag, fn ->
      case :persistent_term.get(flag, :missing) do
        :missing ->
          :persistent_term.put(flag, :present)
          func.()

        _ ->
          :ok
      end
    end)
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
        Enum.any?(@allow_globs, &PathGlob.match?(entry_string, &1, match_dot: true)) do
      entry
    end
  end

  defp erl_args(arg_list) do
    arg_list
    |> Enum.join(" ")
    |> String.to_charlist()
  end
end
