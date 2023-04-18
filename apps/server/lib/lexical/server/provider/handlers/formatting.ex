defmodule Lexical.Server.Provider.Handlers.Formatting do
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.RemoteControl
  alias Lexical.Server.Provider.Env
  alias Lexical.SourceFile

  require Logger

  def handle(%Requests.Formatting{} = request, %Env{} = env) do
    document = request.source_file

    case RemoteControl.Api.format(env.project, document) do
      {:ok, edits} ->
        document_edits = SourceFile.DocumentEdits.new(document, edits)
        response = Responses.Formatting.new(request.id, document_edits)
        Logger.info("Response #{inspect(response)}")
        {:reply, response}

      {:error, reason} ->
        Logger.error("Formatter failed #{inspect(reason)}")

        {:reply, Responses.Formatting.error(request.id, :request_failed, inspect(reason))}
    end
  end
end
