defmodule Lexical.Provider.Handlers.Formatting do
  alias Lexical.Provider.Env
  alias Lexical.CodeMod.Format
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Transport
  require Logger

  def handle(%Requests.Formatting{} = request, %Env{} = env) do
    document = request.source_file
    Logger.info("project path #{inspect(env)}")
    Logger.info("doc path #{document.uri}")

    with {:ok, text_edits} <- Format.text_edits(document, env.project_uri) do
      response = Responses.Formatting.new(request.id, text_edits)
      Logger.info("Response #{inspect(response)}")
      {:reply, response}
    else
      {:error, reason} ->
        Logger.error("Formatter failed #{inspect(reason)}")

        {:reply, Responses.Formatting.error(request.id, :request_failed, inspect(reason))}
    end
  end
end
