defmodule Lexical.Ast.Analysis.Require do
  alias Lexical.Ast
  alias Lexical.Document
  defstruct [:module, :as, :range]

  def new(%Document{} = document, ast, module, as \\ nil) when is_list(module) do
    range = Ast.Range.get(ast, document)
    %__MODULE__{module: module, as: as || module, range: range}
  end
end
