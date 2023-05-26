defmodule Lexical.Document.Location do
  alias Lexical.Document
  alias Lexical.Document.Range

  defstruct [:range, :document, :uri]

  use Lexical.StructAccess

  def new(%Range{} = range, %Document{} = document) do
    %__MODULE__{range: range, document: document}
  end

  def new(%Range{} = range, uri) when is_binary(uri) do
    %__MODULE__{range: range, uri: uri}
  end

  def uri(%__MODULE__{document: %Document{} = document}) do
    document.uri
  end

  def uri(%__MODULE__{} = location) do
    location.uri
  end
end
