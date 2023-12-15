defmodule Lexical.Server.Provider.Handlers.Commands do
  alias Lexical.Formats
  alias Lexical.Project
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types
  alias Lexical.Protocol.Types.ErrorCodes
  alias Lexical.RemoteControl
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Window

  require ErrorCodes
  require Logger

  def names do
    [reindex_name()]
  end

  def reindex_command(%Project{} = project) do
    project_name = Project.name(project)

    Types.Command.new(
      title: "Rebuild #{project_name}'s code search index",
      command: reindex_name()
    )
  end

  def handle(%Requests.ExecuteCommand{} = request, %Env{} = env) do
    response =
      case request.command do
        "Reindex" ->
          Logger.info("Reindex #{Project.name(env.project)}")
          reindex(env.project, request.id)

        invalid ->
          message = "#{invalid} is not a valid command"
          internal_error(request.id, message)
      end

    {:reply, response}
  end

  defp reindex(%Project{} = project, request_id) do
    case :timer.tc(RemoteControl.Api, :reindex, [project]) do
      {elapsed, :ok} ->
        message = "Reindexed #{Project.name(project)} in #{Formats.time(elapsed)}"
        Window.show(:info, message)
        Responses.ExecuteCommand.new(request_id, "ok")

      {_elapsed, error} ->
        Window.error("Indexing #{Project.name(project)} failed")
        Logger.error("Indexing command failed due to #{inspect(error)}")

        internal_error(request_id, "Indexing Failed")
    end
  end

  defp internal_error(request_id, message) do
    Responses.ExecuteCommand.error(request_id, :internal_error, message)
  end

  defp reindex_name do
    "Reindex"
  end
end
