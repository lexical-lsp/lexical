defmodule Lexical.Server.CodeIntelligence.Completion.Translations.StructField do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.StructField

  def translate(%Result.StructField{name: "__struct__"}, _builder, _env) do
    :skip
  end

  def translate(%Result.StructField{} = struct_field, builder, %Env{} = env) do
    builder.plain_text(env, struct_field.name,
      detail: struct_field.name,
      label: struct_field.name,
      kind: :field
    )
  end
end
