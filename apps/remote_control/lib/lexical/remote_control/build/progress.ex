defmodule Lexical.RemoteControl.Build.Progress do
  alias Lexical.RemoteControl
  import Lexical.RemoteControl.Api.Messages

  def report_progress(label, func) when is_function(func) do
    RemoteControl.notify_listener(project_progress(label: label <> ".begin"))
    {_elapsed, result} = :timer.tc(fn -> func.() end)
    RemoteControl.notify_listener(project_progress(label: label <> ".end"))
    result
  end

  def all_ex_files() do
    if Mix.Project.umbrella?() do
      for {app, path} <- Mix.Project.apps_paths() do
        Mix.Project.in_project(app, path, fn _ ->
          Mix.Project.config()
          |> Keyword.fetch!(:elixirc_paths)
          |> Mix.Utils.extract_files(["ex"])
          |> Enum.map(&Path.join(path, &1))
        end)
      end
      |> List.flatten()
    else
      config = Mix.Project.config()
      srcs = config[:elixirc_paths]
      Mix.Utils.extract_files(srcs, ["ex"])
    end
  end
end
