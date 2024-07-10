defmodule Lexical.Server.Provider.Handlers.Formatting do
  alias Lexical.Document.Changes
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.RemoteControl
  alias Lexical.Server.Configuration

  require Logger

  def handle(%Requests.Formatting{} = request, %Configuration{} = config) do
    document = request.document

    case RemoteControl.Api.format(config.project, document) do
      {:ok, %Changes{} = document_edits} ->
        response = Responses.Formatting.new(request.id, document_edits)
        Logger.info("Response #{inspect(response)}")
        {:reply, response}

      {:error, reason} ->
        Logger.error("Formatter failed #{inspect(reason)}")
        {:reply, Responses.Formatting.new(request.id, nil)}
    end
  end
end
