defmodule Lexical.Document.Changes do
  @moduledoc """
  A Document container for text edits.

  If you have a list of text edits in a response, wrap them in this struct and they'll be converted into a list of text edits cleanly.
  """
  defstruct [:document, :edits]
  alias Lexical.Document

  use Lexical.StructAccess

  @type t :: %__MODULE__{
          document: Document.t(),
          edits: [Document.Edit]
        }

  def new(document, edits) do
    %__MODULE__{document: document, edits: edits}
  end
end
