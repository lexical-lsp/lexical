defmodule Lexical.Server.Provider.Handlers.Completion do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Server.CodeIntelligence
  alias Lexical.Server.Configuration

  require Logger

  def handle(%Requests.Completion{} = request, %Configuration{} = config) do
    completions =
      CodeIntelligence.Completion.complete(
        config.project,
        document_analysis(request.document, request.position),
        request.position,
        request.context || Completion.Context.new(trigger_kind: :invoked)
      )

    response = Responses.Completion.new(request.id, completions)
    {:reply, response}
  end

  defp document_analysis(%Document{} = document, %Position{} = position) do
    case Document.Store.fetch(document.uri, :analysis) do
      {:ok, %Document{}, %Ast.Analysis{} = analysis} ->
        Ast.reanalyze_to(analysis, position)

      _ ->
        document
        |> Ast.analyze()
        |> Ast.reanalyze_to(position)
    end
  end
end
