defmodule Lexical.RemoteControl.Analyzer.Uses do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Document.Position

  def at(%Analysis{} = analysis, %Position{} = position) do
    case Analysis.scopes_at(analysis, position) do
      [%Scope{} = scope | _] ->
        Enum.filter(scope.uses, fn use ->
          use_end = use.range.end

          if position.line == use_end.line do
            position.character >= use_end.character
          else
            position.line > use_end.line
          end
        end)

      _ ->
        []
    end
  end
end
