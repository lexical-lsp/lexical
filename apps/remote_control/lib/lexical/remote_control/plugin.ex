defmodule Lexical.RemoteControl.Plugin do
  alias Lexical.Document
  alias Lexical.Plugin
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages

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

        RemoteControl.notify_listener(message)
    end

    Plugin.diagnose(project, on_complete)
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

        RemoteControl.notify_listener(message)
    end

    Plugin.diagnose(document, on_complete)
  end
end
