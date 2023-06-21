defmodule Lexical.Document.Edit do
  @moduledoc """
  A change to a document

  A `Lexical.Document.Edit` represents a single change to a document. It contains
  the new text and a range where the edit applies.
  """
  alias Lexical.Document.Range
  alias Lexical.StructAccess

  defstruct [:text, :range]

  @type t :: %__MODULE__{
          text: String.t(),
          range: Range.t() | nil
        }

  use StructAccess

  @doc "Creates a new edit that replaces all text in the document"
  @spec new(String.t(), Range.t() | nil) :: t
  @spec new(String.t()) :: t
  def new(text) when is_binary(text) do
    %__MODULE__{text: text}
  end

  @doc "Creates a new edit that replaces text in the given range"
  def new(text, %Range{} = range) do
    %__MODULE__{text: text, range: range}
  end

  def new(text, nil) when is_binary(text) do
    %__MODULE__{text: text}
  end
end
