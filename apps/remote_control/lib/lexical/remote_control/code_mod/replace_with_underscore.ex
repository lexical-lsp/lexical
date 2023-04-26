defmodule Lexical.RemoteControl.CodeMod.ReplaceWithUnderscore do
  alias Lexical.RemoteControl.CodeMod.Ast
  alias Lexical.RemoteControl.CodeMod.Diff
  alias Lexical.SourceFile
  alias Lexical.SourceFile.DocumentEdits
  alias Lexical.SourceFile.Edit

  @spec edits(SourceFile.t(), non_neg_integer(), String.t() | atom) ::
          {:ok, DocumentEdits.t()} | :error
  def edits(%SourceFile{} = source_file, line_number, variable_name) do
    variable_name = ensure_atom(variable_name)

    with {:ok, line_text} <- SourceFile.fetch_text_at(source_file, line_number),
         {:ok, line_ast} <- Ast.from(line_text),
         {:ok, transformed_text} <- apply_transform(line_text, line_ast, variable_name) do
      edits = to_edits(line_number, line_text, transformed_text)

      {:ok, DocumentEdits.new(source_file, edits)}
    end
  end

  defp to_edits(line_number, orig_text, fixed_text) do
    for %Edit{text: "_"} = edit <- Diff.diff(orig_text, fixed_text) do
      adjust_line_number(edit, line_number)
    end
  end

  defp ensure_atom(variable_name) when is_binary(variable_name) do
    String.to_atom(variable_name)
  end

  defp ensure_atom(variable_name) when is_atom(variable_name) do
    variable_name
  end

  defp apply_transform(line_text, quoted_ast, unused_variable_name) do
    underscored_variable_name = :"_#{unused_variable_name}"
    leading_indent = leading_indent(line_text)

    Macro.postwalk(quoted_ast, fn
      {^unused_variable_name, meta, nil} ->
        {underscored_variable_name, meta, nil}

      other ->
        other
    end)
    |> Macro.to_string()
    # We're dealing with a single error on a single line.
    # If the line doesn't compile (like it has a do with no end), ElixirSense
    # adds additional lines do documents with errors, so take the first line, as it's
    # the properly transformed source
    |> fetch_line(0)
    |> case do
      {:ok, text} ->
        {:ok, "#{leading_indent}#{text}"}

      error ->
        error
    end
  end

  @indent_regex ~r/^\s+/
  defp leading_indent(line_text) do
    case Regex.scan(@indent_regex, line_text) do
      [indent] -> indent
      _ -> ""
    end
  end

  defp fetch_line(message, line_number) do
    line =
      message
      |> String.split(["\r\n", "\r", "\n"])
      |> Enum.at(line_number)

    case line do
      nil -> :error
      other -> {:ok, other}
    end
  end

  defp adjust_line_number(%Edit{} = text_edit, line_number) do
    text_edit
    |> put_in([:range, :start, :line], line_number)
    |> put_in([:range, :end, :line], line_number)
  end
end
