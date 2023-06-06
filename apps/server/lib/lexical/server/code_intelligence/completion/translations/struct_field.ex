defmodule Lexical.Server.CodeIntelligence.Completion.Translations.StructField do
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Candidate.StructField

  def translate(%Candidate.StructField{name: "__struct__"}, _builder, _env) do
    :skip
  end

  def translate(%Candidate.StructField{} = struct_field, builder, %Env{} = env) do
    builder.plain_text(env, struct_field.name,
      detail: struct_field.name,
      label: struct_field.name,
      kind: :field
    )
  end

  def translate(struct_fields, _builder, %Env{} = env) when is_list(struct_fields) do
    for name <- struct_fields do
      value = to_string(name)

      label = "#{name}: #{value}"
      insert_text = "#{name}: ${1:#{value}}"

      Env.snippet(env, insert_text,
        kind: :field,
        label: label,
        sort_text: label
      )
    end
  end
end
