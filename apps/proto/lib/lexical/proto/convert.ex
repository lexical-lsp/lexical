defmodule Lexical.Proto.Convert do
  alias Lexical.Convertible
  alias Lexical.Document

  def to_lsp(%_{result: result} = response) do
    case Convertible.to_lsp(result) do
      {:ok, converted} ->
        {:ok, Map.put(response, :result, converted)}

      error ->
        error
    end
  end

  def to_lsp(other) do
    Convertible.to_lsp(other)
  end

  def to_native(%{lsp: request_or_notification} = original_request) do
    context_document = Document.Container.context_document(request_or_notification, nil)

    with {:ok, native_request} <- Convertible.to_native(request_or_notification, context_document) do
      updated_request =
        case Map.merge(original_request, Map.from_struct(native_request)) do
          %_{document: _} = updated -> Map.put(updated, :document, context_document)
          updated -> updated
        end

      {:ok, updated_request}
    end
  end
end
