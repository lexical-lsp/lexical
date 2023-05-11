defmodule Lexical.Server.Project.Progress.Support do
  alias Lexical.Server.Project.Progress

  import Lexical.RemoteControl.Api.Messages

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), only: [with_progress: 3]
    end
  end

  def with_progress(project, label, func) when is_function(func, 0) do
    progress_pid = Progress.name(project)

    try do
      send(progress_pid, project_progress(label: label, stage: :begin))
      func.()
    after
      send(progress_pid, project_progress(label: label, stage: :end))
    end
  end
end
