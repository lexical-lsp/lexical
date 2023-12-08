defmodule Lexical.RemoteControl.Analyzer.Aliases do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Analyzer.Alias
  alias Lexical.Ast.Analysis.Analyzer.Scope
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.Analyzer.Scopes

  @blank_doc Document.new("file:///", "", 1)

  @spec at(Analysis.t(), Position.t()) :: %{atom() => module()}
  def at(%Analysis{} = analysis, %Position{} = position) do
    case Scopes.at(analysis, position) do
      [%Scope{} = scope | _] ->
        scope
        |> Scope.alias_map(position)
        |> Map.new(fn {as, %Alias{} = alias} ->
          {as, Alias.to_module(alias)}
        end)

      [] ->
        %{}
    end
  end

  @doc """
  Resolves an alias in the context of a line and a scope
  (used internally when calculating imports)
  """
  def resolve_at(%Scope{} = scope, module, line) do
    position = Position.new(@blank_doc, line, 1)
    aliases = Scope.alias_map(scope, position)

    case module do
      [{:__MODULE__, _, _} | suffix] ->
        current_module =
          aliases
          |> Map.get(:__MODULE__)
          |> Alias.to_module()

        Module.concat([current_module | suffix])

      [prefix | suffix] ->
        case aliases do
          %{^prefix => _} ->
            current_module =
              aliases
              |> Map.get(prefix)
              |> Alias.to_module()

            Module.concat([current_module | suffix])

          _ ->
            Module.concat(module)
        end
    end
  end
end
