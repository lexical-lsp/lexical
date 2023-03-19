defmodule Lexical.Server.Provider.Handlers.CodeAction do
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Server.Provider.CodeAction.ReplaceWithUnderscore
  alias Lexical.Server.Provider.CodeAction.ReplaceWithUnderscore
  alias Lexical.Server.Provider.Env

  require Logger

  @code_actions [ReplaceWithUnderscore]

  def handle(%Requests.CodeAction{} = request, %Env{} = env) do
    code_actions = Enum.flat_map(@code_actions, & &1.apply(request, env))
    reply = Responses.CodeAction.new(request.id, code_actions)

    {:reply, reply}
  end
end
