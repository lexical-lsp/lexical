defmodule Lexical.RemoteControl.Analyzer.Aliases do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Alias
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.Analyzer.Scopes

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
    aliases = Scope.alias_map(scope, line)

    case module do
      # unquote(__MODULE__).SubModule
      [{:unquote, _, [{:__MODULE__, _, _}]} | suffix] ->
        resolve_current_module(aliases, suffix)

      [{:__MODULE__, _, _} | suffix] ->
        resolve_current_module(aliases, suffix)

      [prefix | suffix] ->
        case aliases do
          %{^prefix => _} ->
            current_module = resolve_alias(aliases, prefix, suffix)

            Module.concat([current_module | suffix])

          _ ->
            Module.concat(module)
        end
    end
  end

  defp resolve_current_module(aliases, suffix) do
    resolve_alias(aliases, :__MODULE__, suffix)
  end

  defp resolve_alias(aliases, prefix, suffix) do
    current_module =
      aliases
      |> Map.get(prefix)
      |> Alias.to_module()

    Module.concat([current_module | suffix])
  end
end
