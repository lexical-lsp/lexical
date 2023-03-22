defmodule Lexical.RemoteControl.Bootstrap do
  @moduledoc """
  Bootstraps the remote control node boot sequence.

  We need to first start elixir and mix, then load the project's mix.exs file so we can discover
  the project's code paths, which are then added to the code paths from the language server. At this
  point, it's safe to start the project, as we should have all the code present to compile the system.
  """
  alias Lexical.RemoteControl
  alias Lexical.Project
  require Logger

  def init(%Project{} = project, listener_pid) do
    true = Code.append_path(hex_path())
    RemoteControl.set_project(project)
    RemoteControl.set_project_listener_pid(listener_pid)
    project_root = Project.root_path(project)

    with :ok <- File.cd(project_root),
         {:ok, _} <- Application.ensure_all_started(:elixir),
         {:ok, _} <- Application.ensure_all_started(:mix),
         {:ok, _} <- Application.ensure_all_started(:logger),
         :ok <- Mix.start() do
      Mix.env(:test)
      start_logger(project)
      maybe_change_directory(project)
      Project.ensure_workspace_exists(project)
    end
  end

  defp hex_path() do
    hex_ebin = Path.join(["hex-*", "**", "ebin"])

    [hex_path] =
      Mix.path_for(:archives)
      |> Path.join(hex_ebin)
      |> Path.wildcard()

    hex_path
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
    # app is an umbrella (umbrealls? returns false when started in a subapp)
    # to no avail. This was the only thing that consistently worked
    configured_root =
      RemoteControl.in_mix_project(project, fn _ ->
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
end
