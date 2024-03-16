defmodule Lexical.RemoteControl.CodeMod.Rename.Callable do
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position

  alias Lexical.RemoteControl.CodeIntelligence.Entity

  def resolve(%Analysis{} = analysis, %Position{} = position) do
    case Entity.resolve(analysis, position) do
      {:ok, {callable, module, local_name, _}, range} when callable in [:call] ->
        {:ok, {:call, {module, local_name}}, range}

      _ ->
        {:error, :not_a_callable}
    end
  end
end
