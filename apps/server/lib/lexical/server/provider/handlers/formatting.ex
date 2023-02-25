defmodule Lexical.Server.Provider.Handlers.Formatting do
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.CodeMod.Format
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses

  require Logger

  def handle(%Requests.Formatting{} = request, %Env{} = env) do
    document = request.source_file

    with {:ok, text_edits} <- Format.text_edits(env.project, document) do
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
