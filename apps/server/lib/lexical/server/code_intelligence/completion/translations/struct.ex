defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Struct do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.Struct

  def translate(%Result.Struct{} = struct, builder, %Env{} = env) do
    struct_reference? = Env.in_context?(env, :struct_reference)
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

    builder_opts =
      if struct_reference? do
        [kind: :struct, detail: "#{struct.name} (Struct)", label: "%#{struct.name}"]
      else
        [kind: :module, detail: "#{struct.name} (Module)", label: struct.name]
      end

    if add_curlies? do
      builder.snippet(env, insert_text <> "{$1}", builder_opts)
    else
      builder.plain_text(env, insert_text, builder_opts)
    end
  end
end
