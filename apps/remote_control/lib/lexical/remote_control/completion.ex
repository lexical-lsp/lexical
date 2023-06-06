defmodule Lexical.RemoteControl.Completion do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.CodeIntelligence.Ast
  alias Lexical.RemoteControl.Completion.Candidate

  def elixir_sense_expand(doc_string, %Position{} = position) do
    # Add one to both the line and character, because elixir sense
    # has one-based lines, and the character needs to be after the context,
    # rather than in between.
    line = position.line
    character = position.character
    hint = ElixirSense.Core.Source.prefix(doc_string, line, character)

    if String.trim(hint) == "" do
      []
    else
      doc_string
      |> ElixirSense.suggestions(line, character)
      |> Enum.map(&Candidate.from_elixir_sense/1)
    end
  end

  def struct_fields(%Document{}, %Position{character: nil}) do
    []
  end

  def struct_fields(%Document{} = document, %Position{} = position) do
    context =
      Code.Fragment.surround_context(
        Document.to_string(document),
        {position.line, position.character}
      )

    case matched_alias(context) do
      {:ok, struct_alias} ->
        struct_module = Ast.expand(document, position, struct_alias)

        fields =
          if function_exported?(struct_module, :__struct__, 0) do
            for {field_name, _v} <- Map.from_struct(struct_module.__struct__()), do: field_name
          end

        List.wrap(fields)

      _ ->
        []
    end
  end

  defp matched_alias(%{context: {:local_or_var, '__MODULE__'}}) do
    {:ok, :__MODULE__}
  end

  defp matched_alias(%{context: {:struct, struct}}) do
    struct = struct |> to_string() |> List.wrap() |> Module.concat()
    {:ok, struct}
  end

  defp matched_alias(_), do: :error
end
