defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleOrBehaviour do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.Project.Intelligence

  use Translatable.Impl, for: [Result.Module, Result.Behaviour]

  def translate(%Result.Module{} = module, builder, %Env{} = env) do
    do_translate(module, builder, env)
  end

  def translate(%Result.Behaviour{} = behaviour, builder, %Env{} = env) do
    do_translate(behaviour, builder, env)
  end

  defp do_translate(%_{} = module, builder, %Env{} = env) do
    detail = builder.fallback(module.summary, module.name)
    struct_reference? = Env.struct_reference?(env)
    defines_struct? = Intelligence.defines_struct?(env.project, module.full_name)

    add_curlies? =
      defines_struct? and String.contains?(Env.last_word(env), "%") and
        not String.contains?(env.suffix, "{")

    {insert_text, detail_label} =
      cond do
        struct_reference? and defines_struct? ->
          {module.name, " (Struct)"}

        struct_reference? and Intelligence.child_defines_struct?(env.project, module.full_name) ->
          insert_text = module.name
          {insert_text, " (Module)"}

        true ->
          {module.name, ""}
      end

    insert_text =
      if add_curlies? do
        insert_text <> "{}"
      else
        insert_text
      end

    completion_kind =
      if add_curlies? do
        :struct
      else
        :module
      end

    builder.plain_text(env, insert_text,
      label: module.name,
      kind: completion_kind,
      detail: detail <> detail_label
    )
  end
end
