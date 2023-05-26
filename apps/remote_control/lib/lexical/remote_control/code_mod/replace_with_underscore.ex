defmodule Lexical.RemoteControl.CodeMod.ReplaceWithUnderscore do
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.RemoteControl.CodeMod.Ast

  @spec edits(Document.t(), non_neg_integer(), String.t() | atom) ::
          {:ok, Changes.t()} | :error
  def edits(%Document{} = document, line_number, variable_name) do
    variable_name = ensure_atom(variable_name)

    case apply_transform(document, line_number, variable_name) do
      {:ok, edits} ->
        {:ok, Changes.new(document, edits)}

      error ->
        error
    end
  end

  defp ensure_atom(variable_name) when is_binary(variable_name) do
    String.to_atom(variable_name)
  end

  defp ensure_atom(variable_name) when is_atom(variable_name) do
    variable_name
  end

  defp apply_transform(document, line_number, unused_variable_name) do
    underscored_variable_name = :"_#{unused_variable_name}"

    result =
      Ast.traverse_line(document, line_number, [], fn
        {{^unused_variable_name, _meta, nil} = node, _} = zipper, patches ->
          [patch] = Sourceror.Patch.rename_identifier(node, underscored_variable_name)
          {zipper, [patch | patches]}

        zipper, acc ->
          {zipper, acc}
      end)

    with {:ok, _, patches} <- result do
      Ast.patches_to_edits(patches)
    end
  end
end
