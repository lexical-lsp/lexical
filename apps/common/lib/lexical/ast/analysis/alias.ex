defmodule Lexical.Ast.Analysis.Alias do
  defstruct [:module, :as, :line]

  @type t :: %__MODULE__{}

  def new(module, as, line) when is_list(module) and is_atom(as) and line > 0 do
    %__MODULE__{module: module, as: as, line: line}
  end

  def to_module(%__MODULE__{} = alias) do
    Module.concat(alias.module)
  end
end
