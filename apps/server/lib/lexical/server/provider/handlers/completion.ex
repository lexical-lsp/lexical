defmodule Lexical.Server.Provider.Handlers.Completion do
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Server.CodeIntelligence
  alias Lexical.Server.Provider.Env

  require Logger

  def handle(%Requests.Completion{} = request, %Env{} = env) do
    completions =
      CodeIntelligence.Completion.complete(
        env.project,
        request.document,
        request.position,
        request.context || Completion.Context.new(trigger_kind: :invoked)
      )

    response = Responses.Completion.new(request.id, completions)
    {:reply, response}
  end
end
