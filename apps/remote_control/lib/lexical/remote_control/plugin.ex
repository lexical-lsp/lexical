defmodule Lexical.RemoteControl.Plugin do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Plugin.Runner

  import Messages

  def diagnose(%Project{} = project, build_number) do
    on_complete = fn
      [] ->
        :ok

      [_ | _] = diagnostics ->
        message =
          project_diagnostics(
            project: project,
            build_number: build_number,
            diagnostics: diagnostics
          )

        RemoteControl.broadcast(message)
    end

    Runner.diagnose(project, on_complete)
  end

  def diagnose(%Project{} = project, build_number, %Document{} = document) do
    on_complete = fn
      [] ->
        :ok

      [_ | _] = diagnostics ->
        message =
          file_diagnostics(
            project: project,
            build_number: build_number,
            uri: document.uri,
            diagnostics: diagnostics
          )

        RemoteControl.broadcast(message)
    end

    Runner.diagnose(document, on_complete)
  end
end
