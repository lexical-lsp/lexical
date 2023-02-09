defmodule Lexical.Provider.Handlers.Completion do
  alias Lexical.CodeIntelligence
  alias Lexical.Provider.Env
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses

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
