defmodule Lexical.Server.Provider.Handlers do
  alias Lexical.Protocol.Requests
  alias Lexical.Server.Provider.Handlers

  def for_request(%_{} = request) do
    case request do
      %Requests.FindReferences{} ->
        {:ok, Handlers.FindReferences}

      %Requests.Formatting{} ->
        {:ok, Handlers.Formatting}

      %Requests.CodeAction{} ->
        {:ok, Handlers.CodeAction}

      %Requests.CodeLens{} ->
        {:ok, Handlers.CodeLens}

      %Requests.Completion{} ->
        {:ok, Handlers.Completion}

      %Requests.GoToDefinition{} ->
        {:ok, Handlers.GoToDefinition}

      %Requests.Hover{} ->
        {:ok, Handlers.Hover}

      %Requests.ExecuteCommand{} ->
        {:ok, Handlers.Commands}

      %Requests.Rename{} ->
        {:ok, Handlers.Rename}

      %request_module{} ->
        {:error, {:unhandled, request_module}}
    end
  end
end
