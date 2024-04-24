defmodule Lexical.Ast.Analysis.Alias do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  defstruct [:module, :as, :range]

  @type t :: %__MODULE__{
          module: [atom],
          as: module(),
          range: Range.t()
        }

  def new(%Document{} = document, ast, module, as) when is_list(module) do
    range = range_for_ast(document, ast, module, as)
    %__MODULE__{module: module, as: as, range: range}
  end

  def to_module(%__MODULE__{} = alias) do
    Module.concat(alias.module)
  end

  @implicit_aliases [:__MODULE__, :"@for", :"@protocol"]
  defp range_for_ast(document, ast, _alias, as) when as in @implicit_aliases do
    range_for_implicit_alias(document, ast)
  end

  defp range_for_ast(document, ast, alias, _as) do
    if List.last(alias) == alias do
      range_for_implicit_alias(document, ast)
    else
      range_for_explicit_alias(document, ast)
    end
  end

  defp range_for_explicit_alias(%Document{} = document, ast) do
    case Ast.Range.fetch(ast, document) do
      {:ok, %Range{end: end_pos} = range} ->
        %Range{range | end: %Position{end_pos | character: end_pos.character}}

      _ ->
        nil
    end
  end

  defp range_for_implicit_alias(%Document{} = document, ast) do
    with [line: line, column: start_column] <- Sourceror.get_start_position(ast),
         {:ok, line_text} <- Document.fetch_text_at(document, line) do
      end_column = String.length(line_text)

      Range.new(
        Position.new(document, line, start_column),
        Position.new(document, line, end_column)
      )
    else
      _ ->
        nil
    end
  end
end
