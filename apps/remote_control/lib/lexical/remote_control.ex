defmodule Lexical.RemoteControl do
  @moduledoc """
  The remote control boots another elixir application in a separate VM, injects
  the remote control application into it and allows the language server to execute tasks in the
  context of the remote VM.
  """

  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build

  @env Mix.env()
  @allowed_apps ~w(path_glob elixir_sense)a
  @remote_apps ~w(remote_control common common_protocol)a

  @localhost_charlist '127.0.0.1'

  def start_link(%Project{} = project, project_listener) do
    :ok = ensure_epmd_started()
    entropy = :rand.uniform(65_536)

    start_net_kernel(project, entropy)

    node_name = String.to_charlist("#{Project.name(project)}")
    {:ok, paths} = system_paths(project)

    erl_args =
      erl_args([
        "-hosts #{@localhost_charlist}",
        "-setcookie #{Node.get_cookie()}",
        "-sbwt none",
        "-path #{paths}",
        "-noshell"
      ])

    apps_to_start = [:elixir | @allowed_apps] ++ @remote_apps ++ [:runtime_tools]

    with {:ok, node} <- :slave.start_link(@localhost_charlist, node_name, erl_args),
         :ok <- :rpc.call(node, :code, :add_paths, [glob_paths()]),
         :ok <-
           :rpc.call(node, namespace_module(RemoteControl.Bootstrap), :init, [
             project,
             project_listener
           ]),
         :ok <- ensure_apps_started(node, apps_to_start) do
      {:ok, node}
    end
  end

  def in_mix_project(fun) when is_function(fun) do
    in_mix_project(get_project(), fun)
  end

  def in_mix_project(%Project{} = project, fun) do
    # Locking on the build make sure we don't get a conflict on the mix.exs being
    # already defined

    Build.with_lock(fn ->
      build_path = Project.build_path(project)
      project_root = Project.root_path(project)

      project
      |> Project.name()
      |> String.to_atom()
      |> Mix.Project.in_project(project_root, [build_path: build_path], fun)
    end)
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
    project
    |> node_name()
    |> :slave.stop()
  end

  def call(%Project{} = project, m, f, a \\ []) do
    # If a module is part of argument list then it
    # must be namespaced at the callsite with namespace_module()
    project
    |> node_name()
    |> :erpc.call(namespace_module(m), f, a)
  end

  def namespace_module(module) do
    unless @env == :dev do
      module
    else
      # Assumption is that if you are using this function then the
      # module *needs* to be casted
      case Module.split(module) do
        ["Lexical" | rest] -> Module.concat(["LexicalNamespace" | rest])
        ["LexicalNamespace" | rest] -> Module.concat(["Lexical" | rest])
        # Something else like Elixir.GenServer
        _ -> module
      end
    end
  end

  def namespace_struct(%unknown_module{} = struct) do
    unless @env == :dev do
      struct
    else
      known_module = namespace_module(unknown_module)

      unless Code.ensure_compiled?(known_module) do
        raise ArgumentError,
              "Expected to know module #{known_module} but no definition was found."
      end

      if function_exported?(known_module, :cast_from_rpc, 1) do
        # Struct might have nested structs, call module function
        known_module.cast_from_rpc(struct)
      else
        # General case scenario, just re-cast
        struct(known_module, Map.from_struct(struct))
      end
    end
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

  @build_path Mix.Project.build_path()
  @umbrella_root Application.compile_env(:remote_control, :umbrella_root)
  @build_path_relative Path.relative_to(@build_path, @umbrella_root)
  def glob_paths do
    unless @env == :dev do
      app_globs =
        Enum.map(@allowed_apps ++ @remote_apps, fn app_name -> "/**/#{app_name}*/ebin" end)

      for entry <- :code.get_path(),
          entry_string = List.to_string(entry),
          entry_string != ".",
          Enum.any?(app_globs, &PathGlob.match?(entry_string, &1, match_dot: true)) do
        entry
      end
    else
      app_globs = Enum.map(@allowed_apps, fn app_name -> "/**/#{app_name}*/ebin" end)

      allowed_paths =
        for entry <- :code.get_path(),
            entry_string = List.to_string(entry),
            entry_string != ".",
            Enum.any?(app_globs, &PathGlob.match?(entry_string, &1, match_dot: true)) do
          entry
        end

      remote_paths =
        Enum.map(@remote_apps, fn app_name ->
          # Path per config/dev.exs
          Path.join([
            @build_path,
            "namespaced",
            @build_path_relative,
            "lib",
            "#{app_name}",
            "ebin"
          ])
          |> String.to_charlist()
        end)

      allowed_paths ++ remote_paths
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
           {:ok, elixir} <- elixir_executable(project),
           {:ok, paths} <- elixir_code_paths(project, elixir) do
        {:ok, format_paths(paths)}
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

  defp format_paths(paths_as_charlists) do
    Enum.map_join(paths_as_charlists, " ", &Path.expand/1)
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
    # disabling this because we're going to immediately add another version manager
    # credo:disable-for-next-line Credo.Check.Refactor.CondStatements
    cond do
      asdf?() ->
        :asdf

      true ->
        :none
    end
  end

  defp asdf?(), do: not is_nil(System.find_executable("asdf"))
end
