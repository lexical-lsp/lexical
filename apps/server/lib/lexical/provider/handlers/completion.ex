defmodule Lexical.Provider.Handlers.Completion do
  alias Lexical.SourceFile.Conversions
  alias Lexical.Project
  alias Lexical.Provider.Env
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Completion
  alias Lexical.RemoteControl

  require Logger

  def handle(%Requests.Completion{} = request, %Env{} = env) do
    response = fake_completion_response(request)

    {:reply, response}
  end

  defp fake_completion_response(%Requests.Completion{} = request) do
    Responses.Completion.new(request.id, [
      fake_completion_item()
    ])
  end

  defp fake_completion_item do
    item = Completion.Item.new(label: "FakeCompletion", detail: "Fake completions", kind: :module)
  end
end
