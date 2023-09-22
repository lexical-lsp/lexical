defmodule Lexical.Server.CodeIntelligence.Completion.Translations.MapField do
  alias Lexical.Ast.Env
  alias Lexical.Completion.Translatable
  alias Lexical.RemoteControl.Completion.Candidate

  defimpl Translatable, for: Candidate.MapField do
    def translate(%Candidate.MapField{} = map_field, builder, %Env{} = env) do
      builder.plain_text(env, map_field.name,
        detail: map_field.name,
        label: map_field.name,
        kind: :field
      )
    end
  end
end
