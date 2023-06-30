defmodule Lexical.RemoteControl.Bootstrap do
  @moduledoc """
  Bootstraps the remote control node boot sequence.

  We need to first start elixir and mix, then load the project's mix.exs file so we can discover
  the project's code paths, which are then added to the code paths from the language server. At this
  point, it's safe to start the project, as we should have all the code present to compile the system.
  """
  alias Lexical.Project
  alias Lexical.RemoteControl
  require Logger

  def init(%Project{} = project, listener_pid, remote_control_config) do
    maybe_append_hex_path()

    RemoteControl.set_project_listener_pid(listener_pid)
    Application.put_all_env(remote_control: remote_control_config)

    project_root = Project.root_path(project)

    with :ok <- File.cd(project_root),
         {:ok, _} <- Application.ensure_all_started(:elixir),
         {:ok, _} <- Application.ensure_all_started(:mix),
         {:ok, _} <- Application.ensure_all_started(:logger) do
      project = maybe_load_mix_exs(project)
      RemoteControl.set_project(project)
      Mix.env(:test)
      ExUnit.start()
      start_logger(project)
      maybe_change_directory(project)
      Project.ensure_workspace(project)
    end
  end

  defp maybe_append_hex_path do
    hex_ebin = Path.join(["hex-*", "**", "ebin"])

    hex_path =
      :archives
      |> Mix.path_for()
      |> Path.join(hex_ebin)
      |> Path.wildcard()

    case hex_path do
      [archives] -> Code.append_path(archives)
      _ -> :ok
    end
  end

  defp start_logger(%Project{} = project) do
    log_file_name =
      project
      |> Project.workspace_path("project.log")
      |> String.to_charlist()

    handler_name = :"#{Project.name(project)}_handler"

    config = %{
      config: %{
        file: log_file_name,
        max_no_bytes: 1_000_000,
        max_no_files: 1
      },
      level: :info
    }

    :logger.add_handler(handler_name, :logger_std_h, config)
  end

  defp maybe_change_directory(%Project{} = project) do
    current_dir = File.cwd!()

    # Note about the following code:
    # I tried a bunch of stuff to get it to work, like checking if the
    # app is an umbrella (umbrealla? returns false when started in a subapp)
    # to no avail. This was the only thing that consistently worked
    {:ok, configured_root} =
      RemoteControl.Mix.in_project(project, fn _ ->
        Mix.Project.config()
        |> Keyword.get(:config_path)
        |> Path.dirname()
        |> Path.join("..")
        |> Path.expand()
      end)

    unless current_dir == configured_root do
      File.cd!(configured_root)
    end
  end

  defp maybe_load_mix_exs(%Project{} = project) do
    # The reason this function exists is to support projects that have the same name as
    # one of their dependencies. Prior to this, the project name was based off the directory
    # name of the project, and if that's the same as a dependency, the mix project stack will
    # raise an error during `deps.safe_compile`, as a project with the same name was already defined.
    # Mix itself uses the name of the module that the mix.exs defines as the project name, and I figured
    # this was a safe default.

    with path when is_binary(path) <- Project.mix_exs_path(project),
         compiled = Code.compile_file(path),
         {:ok, project_module} <- find_mix_project_module(compiled) do
      # We've found the mix project module, but it's now been added to the
      # project stack. We need to clear the stack because we use `in_mix_project`, and
      # that will fail if the current project is already in the project stack.
      # Restarting mix will clear the stack without using private APIs.
      Application.stop(:mix)
      Application.ensure_all_started(:mix)
      Project.set_project_module(project, project_module)
    else
      _ ->
        project
    end
  end

  defp find_mix_project_module(module_list) do
    case Enum.find(module_list, &project_module?/1) do
      {module, _bytecode} -> {:ok, module}
      nil -> :error
    end
  end

  defp project_module?({module, _bytecode}) do
    function_exported?(module, :project, 0)
  end

  defp project_module?(_), do: false
end
