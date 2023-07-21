defmodule Lexical.RemoteControl do
  @moduledoc """
  The remote control boots another elixir application in a separate VM, injects
  the remote control application into it and allows the language server to execute tasks in the
  context of the remote VM.
  """

  alias Lexical.Project
  alias Lexical.RemoteControl.ProjectNode
  require Logger

  @excluded_apps [:patch, :nimble_parsec]
  @allowed_apps [:remote_control | Mix.Project.deps_apps()] -- @excluded_apps

  @app_globs Enum.map(@allowed_apps, fn app_name -> "/**/#{app_name}*/ebin" end)

  def start_link(%Project{} = project, project_listener) do
    :ok = ensure_epmd_started()
    entropy = :rand.uniform(65_536)
    start_net_kernel(project, entropy)

    apps_to_start = [:elixir | @allowed_apps] ++ [:runtime_tools]
    node = node_name(project)

    with {:ok, node_pid} <- ProjectNode.start(project, project_listener, glob_paths()),
         :ok <- ensure_apps_started(node, apps_to_start) do
      {:ok, node, node_pid}
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

  defdelegate stop(project), to: ProjectNode

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
    version_manager = version_manager()
    env = reset_env(version_manager, root_path)

    path_result =
      case version_manager() do
        :asdf ->
          case System.cmd("asdf", ~w(which elixir), cd: root_path, env: env) do
            {path, 0} ->
              String.trim(path)

            _ ->
              nil
          end

        :rtx ->
          case System.cmd("rtx", ~w(which elixir), cd: root_path, env: env) do
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
        {:ok, executable, env}
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

  # We launch lexical by asking the version managers to provide an environment,
  # which contains path munging. This initial environment is present in the running
  # VM, and needs to be undone so we can find the correct elixir executable in the project.
  defp reset_env(:asdf, _root_path) do
    orig_path = System.get_env("PATH_SAVE", System.get_env("PATH"))

    Enum.map(System.get_env(), fn
      {"ASDF_ELIXIR_VERSION", _} -> {"ASDF_ELIXIR_VERSION", nil}
      {"ASDF_ERLANG_VERSION", _} -> {"ASDF_ERLANG_VERSION", nil}
      {"PATH", _} -> {"PATH", orig_path}
      other -> other
    end)
  end

  defp reset_env(:rtx, root_path) do
    {env, _} = System.cmd("rtx", ~w(), cd: root_path)

    env
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(fn "export " <> key_and_value ->
      [key, value] =
        key_and_value
        |> String.split("=", parts: 2)
        |> Enum.map(&String.trim/1)

      {key, value}
    end)
  end

  defp reset_env(_, _) do
    System.get_env()
  end
end
