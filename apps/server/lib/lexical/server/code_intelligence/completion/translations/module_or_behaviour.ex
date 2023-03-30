defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleOrBehaviour do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translator
  alias Lexical.Server.Project.Intelligence

  use Translator, for: [Result.Module, Result.Behaviour]

  def translate(%Result.Module{} = module, %Env{} = env) do
    do_translate(module, env)
  end

  def translate(%Result.Behaviour{} = behaviour, %Env{} = env) do
    do_translate(behaviour, env)
  end

  defp do_translate(%_{} = module, %Env{} = env) do
    detail = fallback(module.summary, module.name)
    struct_reference? = Env.struct_reference?(env)
    defines_struct? = Intelligence.defines_struct?(env.project, module.full_name)
    add_curlies? = defines_struct? and not String.contains?(env.suffix, "{")

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
      if defines_struct? do
        :struct
      else
        :module
      end

    plain_text(insert_text,
      label: module.name,
      kind: completion_kind,
      detail: detail <> detail_label
    )
  end
end
