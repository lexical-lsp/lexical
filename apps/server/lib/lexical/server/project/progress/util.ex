defmodule Lexical.Server.Project.Progress.Util do
  alias Lexical.Server.Project.Progress

  import Lexical.RemoteControl.Api.Messages

  def with_progress(project, label, func) do
    progress_pid = Progress.name(project)

    send(progress_pid, project_progress(label: label <> ".begin"))
    result = func.()
    send(progress_pid, project_progress(label: label <> ".end"))

    result
  end
end
