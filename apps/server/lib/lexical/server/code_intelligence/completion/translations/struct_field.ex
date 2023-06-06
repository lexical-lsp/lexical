defmodule Lexical.Server.CodeIntelligence.Completion.Translations.StructField do
  alias Future.Code, as: Code
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Candidate.StructField

  def translate(%Candidate.StructField{name: "__struct__"}, _builder, _env) do
    :skip
  end

  def translate(%Candidate.StructField{call?: false} = struct_field, builder, %Env{} = env) do
    name = struct_field.name
    value = to_string(name)

    builder_opts = [
      kind: :field,
      label: "#{name}: #{value}"
    ]

    insert_text = "#{name}: ${1:#{value}}"
    range = edit_range(env)

    builder.text_edit_snippet(env, insert_text, range, builder_opts)
  end

  def translate(%Candidate.StructField{} = struct_field, builder, %Env{} = env) do
    builder.plain_text(env, struct_field.name,
      detail: struct_field.name,
      label: struct_field.name,
      kind: :field
    )
  end

  def edit_range(env) do
    prefix_end = env.position.character

    case Code.Fragment.cursor_context(env.prefix) do
      {:local_or_var, field_char} ->
        edit_begin = env.position.character - length(field_char)
        {edit_begin, prefix_end}

      _ ->
        {prefix_end, prefix_end}
    end
  end
end
