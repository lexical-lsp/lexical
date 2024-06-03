defmodule Lexical.Ast.Analysis.Use do
  alias Lexical.Ast
  alias Lexical.Document
  defstruct [:module, :range, :opts]

  def new(%Document{} = document, ast, module, opts) do
    range = Ast.Range.get(ast, document)
    %__MODULE__{range: range, module: module, opts: opts}
  end
end
