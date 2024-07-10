defmodule Lexical.Server.CodeIntelligence.Completion.Translations.MapField do
  alias Lexical.Ast.Env
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  defimpl Translatable, for: Candidate.MapField do
    def translate(%Candidate.MapField{} = map_field, builder, %Env{} = env) do
      builder.text_edit(env, map_field.name, range(env),
        detail: map_field.name,
        label: map_field.name,
        kind: :field
      )
    end

    defp range(%Env{} = env) do
      case Env.prefix_tokens(env, 1) do
        # ensure the text edit doesn't overwrite the dot operator
        # when we're completing immediately after it: some_map.|
        [{:operator, :., {_line, char}}] ->
          {char + 1, env.position.character}

        [{_, _, {_line, char}}] ->
          {char, env.position.character}
      end
    end
  end
end
