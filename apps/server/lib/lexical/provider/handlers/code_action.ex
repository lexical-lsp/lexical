defmodule Lexical.Provider.Handlers.CodeAction do
  alias Lexical.Provider.CodeAction.ReplaceWithUnderscore
  alias Lexical.Provider.Env
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Provider.CodeAction.ReplaceWithUnderscore

  require Logger

  def handle(%Requests.CodeAction{} = request, %Env{}) do
    code_actions = ReplaceWithUnderscore.apply(request)
    reply = Responses.CodeAction.new(request.id, code_actions)

    {:reply, reply}
  end
end
