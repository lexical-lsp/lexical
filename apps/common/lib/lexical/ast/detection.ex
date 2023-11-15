defmodule Lexical.Ast.Detection do
  @moduledoc """
  A behavior for context detection

  A context recognizer can recognize the type of code at a current position.
  It is useful for identifying the "part of speech" of a position.

  Note: a given context might be detected by more than one module.
  """

  alias Lexical.Document
  alias Lexical.Document.Position

  @doc """
  Returns true if the given position is detected by the current module
  """
  @callback detected?(Document.t(), Position.t()) :: boolean()
end
