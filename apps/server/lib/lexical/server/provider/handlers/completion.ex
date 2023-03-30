defmodule Lexical.Server.Provider.Handlers.Completion do
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Server.CodeIntelligence
  alias Lexical.Server.Provider.Env

  require Logger

  def handle(%Requests.Completion{} = request, %Env{} = env) do
    completions =
      CodeIntelligence.Completion.complete(
        env.project,
        request.source_file,
        request.position,
        request.context
      )

    response = Responses.Completion.new(request.id, completions)
    Logger.info("Got #{Jason.encode!(completions)}")
    {:reply, response}
  end
end
