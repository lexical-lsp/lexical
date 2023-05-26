defmodule Lexical.Convertible.Helpers do
  alias Lexical.Document

  def apply(%{} = map, func, context_document) do
    Enum.reduce_while(map, [], fn {key, value}, acc ->
      context_document = Document.Container.context_document(value, context_document)

      case func.(value, context_document) do
        {:ok, native} ->
          {:cont, [{key, native} | acc]}

        error ->
          {:halt, error}
      end
    end)
  end

  def apply(enumerable, func, context_document) do
    result =
      Enum.reduce_while(enumerable, [], fn elem, acc ->
        context_document = Document.Container.context_document(elem, context_document)

        case func.(elem, context_document) do
          {:ok, native} ->
            {:cont, [native | acc]}

          error ->
            {:halt, error}
        end
      end)

    case result do
      l when is_list(l) ->
        Enum.reverse(l)

      error ->
        error
    end
  end
end

defprotocol Lexical.Convertible do
  alias Lexical.Document

  @fallback_to_any true

  @type t :: term()
  @type native :: term()
  @type lsp :: term()

  @type native_response :: {:ok, native()} | {:error, term}
  @type lsp_response :: {:ok, lsp()} | {:error, term}

  @doc """
  Converts the structure to a native implementation
  """
  @spec to_native(t, Document.Container.maybe_context_document()) :: native_response()
  def to_native(t, context_document)

  @doc """
  Converts the native representation to a LSP compatible struct
  """
  @spec to_lsp(t, Document.Container.maybe_context_document()) :: lsp_response()
  def to_lsp(t, context_document)
end

defimpl Lexical.Convertible, for: List do
  alias Lexical.Convertible
  alias Lexical.Convertible.Helpers

  def to_native(l, context_document) do
    case Helpers.apply(l, &Convertible.to_native/2, context_document) do
      l when is_list(l) ->
        {:ok, l}

      error ->
        error
    end
  end

  def to_lsp(l, context_document) do
    case Helpers.apply(l, &Convertible.to_lsp/2, context_document) do
      l when is_list(l) ->
        {:ok, l}

      error ->
        error
    end
  end
end

defimpl Lexical.Convertible, for: Map do
  alias Lexical.Convertible
  alias Lexical.Convertible.Helpers

  def to_native(map, context_document) do
    case Helpers.apply(map, &Convertible.to_native/2, context_document) do
      l when is_list(l) -> {:ok, Map.new(l)}
      error -> error
    end
  end

  def to_lsp(map, context_document) do
    case Helpers.apply(map, &Convertible.to_lsp/2, context_document) do
      l when is_list(l) -> {:ok, Map.new(l)}
      error -> error
    end
  end
end

defimpl Lexical.Convertible, for: Any do
  alias Lexical.Convertible
  alias Lexical.Document
  alias Lexical.Convertible.Helpers

  def to_native(%_struct_module{} = struct, context_document) do
    context_document = Document.Container.context_document(struct, context_document)

    result =
      struct
      |> Map.from_struct()
      |> Helpers.apply(&Convertible.to_native/2, context_document)

    case result do
      l when is_list(l) ->
        {:ok, Map.merge(struct, Map.new(l))}

      error ->
        error
    end
  end

  def to_native(any, _context_document) do
    {:ok, any}
  end

  def to_lsp(%_struct_module{} = struct, context_document) do
    context_document = Document.Container.context_document(struct, context_document)

    result =
      struct
      |> Map.from_struct()
      |> Helpers.apply(&Convertible.to_lsp/2, context_document)

    case result do
      l when is_list(l) ->
        {:ok, Map.merge(struct, Map.new(result))}

      error ->
        error
    end
  end

  def to_lsp(any, _context_document) do
    {:ok, any}
  end
end
