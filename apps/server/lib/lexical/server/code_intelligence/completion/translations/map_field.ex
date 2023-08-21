defmodule Lexical.Server.CodeIntelligence.Completion.Translations.MapField do
  alias Lexical.Ast.Env
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Candidate.MapField

  def translate(%Candidate.MapField{} = map_field, builder, %Env{} = env) do
    builder.plain_text(env, map_field.name,
      detail: map_field.name,
      label: map_field.name,
      kind: :field
    )
  end
end
