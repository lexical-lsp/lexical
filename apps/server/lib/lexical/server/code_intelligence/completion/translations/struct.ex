defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Struct do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.Struct

  def translate(%Result.Struct{} = struct, builder, %Env{} = env) do
    struct_reference? = Env.struct_reference?(env)
    add_curlies? = struct_reference? and not String.contains?(env.suffix, "{")

    insert_text =
      cond do
        struct_reference? and not String.contains?(env.prefix, ".") ->
          "%#{struct.name}"

        struct_reference? ->
          "#{struct.name}"

        true ->
          struct.name
      end

    insert_text =
      if add_curlies? do
        insert_text <> "{}"
      else
        insert_text
      end

    builder.plain_text(env, insert_text,
      detail: "#{struct.name} (Struct)",
      kind: :struct,
      label: struct.name
    )
  end
end
