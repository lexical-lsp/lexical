defmodule Lexical do
  @moduledoc """
  Shared data structures and utilities for the Lexical Language Server.

  If you're building a plugin, You're probably going to want to look at the documentation
  for core data structures like

  `Lexical.Project` - The lexical project structure

  `Lexical.Document` - A text document, given to you by the language server

  `Lexical.Document.Position` - A position inside a document

  `Lexical.Document.Range` - A range of text inside a document
  """
  @typedoc "A string representation of a uri"
  @type uri :: String.t()

  @typedoc "A string representation of a path on the filesystem"
  @type path :: String.t()
end
