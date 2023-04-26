defmodule Lexical.Document.Location do
  alias Lexical.Document
  alias Lexical.Document.Range

  defstruct [:range, :source_file, :uri]

  use Lexical.StructAccess

  def new(%Range{} = range, %Document{} = source_file) do
    %__MODULE__{range: range, source_file: source_file}
  end

  def new(%Range{} = range, uri) when is_binary(uri) do
    %__MODULE__{range: range, uri: uri}
  end

  def uri(%__MODULE__{source_file: %Document{} = source_file}) do
    source_file.uri
  end

  def uri(%__MODULE__{} = location) do
    location.uri
  end
end
