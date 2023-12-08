defmodule Lexical.RemoteControl.Analyzer.Scopes do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  def at(%Analysis{scopes: scopes}, %Position{} = position) do
    scopes
    |> Enum.filter(fn %Scope{range: range} = scope ->
      scope.id == :global or Range.contains?(range, position)
    end)
    |> Enum.sort_by(
      fn
        %Scope{id: :global} -> 0
        %Scope{range: range} -> {range.start.line, range.start.character}
      end,
      :desc
    )
  end
end
