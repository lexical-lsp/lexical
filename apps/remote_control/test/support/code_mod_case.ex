defmodule Lexical.Test.CodeMod.Case do
  alias Lexical.Document
  alias Lexical.Test.CodeSigil

  use ExUnit.CaseTemplate

  using do
    quote do
      import Lexical.Test.Fixtures
      import unquote(CodeSigil), only: [sigil_q: 2]

      def apply_code_mod(_, _, _) do
        {:error, "You must implement apply_code_mod/3"}
      end

      defoverridable apply_code_mod: 3

      def modify(original, options \\ []) do
        with {:ok, ast} <- maybe_convert_to_ast(original, options),
             {:ok, edits} <- apply_code_mod(original, ast, options) do
          {:ok, unquote(__MODULE__).apply_edits(original, edits, options)}
        end
      end

      defp maybe_convert_to_ast(code, options) do
        alias Lexical.RemoteControl.CodeMod.Ast

        if Keyword.get(options, :convert_to_ast, true) do
          Ast.from(code)
        else
          {:ok, nil}
        end
      end
    end
  end

  def apply_edits(original, text_edits, opts) do
    source_file = Document.new("file:///file.ex", original, 0)
    {:ok, edited_source_file} = Document.apply_content_changes(source_file, 1, text_edits)
    edited_source = Document.to_string(edited_source_file)

    if Keyword.get(opts, :trim, true) do
      String.trim(edited_source)
    else
      edited_source
    end
  end
end
