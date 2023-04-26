defmodule Lexical.Proto.Convert do
  alias Lexical.Convertible
  alias Lexical.DocumentContainer

  def to_lsp(%_{result: result} = response) do
    context_document = DocumentContainer.context_document(result, nil)

    case Convertible.to_lsp(result, context_document) do
      {:ok, converted} ->
        {:ok, Map.put(response, :result, converted)}

      error ->
        error
    end
  end

  def to_lsp(other) do
    context_document = DocumentContainer.context_document(other, nil)
    Convertible.to_lsp(other, context_document)
  end

  def to_native(%{lsp: request_or_notification} = original_request) do
    context_document = DocumentContainer.context_document(request_or_notification, nil)

    with {:ok, native_request} <- Convertible.to_native(request_or_notification, context_document) do
      updated_request =
        case Map.merge(original_request, Map.from_struct(native_request)) do
          %_{source_file: _} = updated -> Map.put(updated, :source_file, context_document)
          updated -> updated
        end

      {:ok, updated_request}
    end
  end
end
