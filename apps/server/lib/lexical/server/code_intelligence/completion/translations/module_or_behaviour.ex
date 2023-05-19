defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleOrBehaviour do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations
  alias Lexical.Server.Project.Intelligence

  use Translatable.Impl, for: [Result.Module, Result.Behaviour, Result.Protocol]

  def translate(%Result.Module{} = module, builder, %Env{} = env) do
    do_translate(module, builder, env)
  end

  def translate(%Result.Behaviour{} = behaviour, builder, %Env{} = env) do
    do_translate(behaviour, builder, env)
  end

  def translate(%Result.Protocol{} = protocol, builder, %Env{} = env) do
    do_translate(protocol, builder, env)
  end

  defp do_translate(%_{} = module, builder, %Env{} = env) do
    struct_reference? = Env.in_context?(env, :struct_reference)

    defines_struct? = Intelligence.defines_struct?(env.project, module.full_name)

    cond do
      struct_reference? and defines_struct? ->
        struct_completion(builder, env, module.name)

      struct_reference? and
          immediate_descentent_defines_struct?(env.project, module.full_name) ->
        env.project
        |> immediate_descendent_struct_modules(module.full_name)
        |> Enum.map(fn child_module_name ->
          local_name = local_module_name(module.full_name, child_module_name)
          struct_completion(builder, env, local_name)
        end)

      true ->
        detail = builder.fallback(module.summary, module.name)
        module_completion(builder, env, module.name, detail)
    end
  end

  defp struct_completion(builder, %Env{} = env, module_name) do
    insert_text =
      if Translations.Struct.add_percent?(env) do
        "%" <> module_name
      else
        module_name
      end

    completion_opts = [
      label: "%" <> module_name,
      kind: :struct,
      sort_text: module_name,
      detail: module_name <> " (Struct)"
    ]

    if Translations.Struct.add_curlies?(env) do
      builder.snippet(env, insert_text <> "{$1}", completion_opts)
    else
      builder.plain_text(env, insert_text, completion_opts)
    end
  end

  defp module_completion(builder, %Env{} = env, module_name, detail) do
    builder.plain_text(env, module_name, label: module_name, kind: :module, detail: detail)
  end

  defp local_module_name(parent_module, child_module) do
    # Returns the "local" module name, so if you're completing
    # Types.Som and the module completion is "Types.Something.Else",
    # "Something.Else" is returned.

    parent_pieces = String.split(parent_module, ".")
    parent_pieces = Enum.take(parent_pieces, length(parent_pieces) - 1)
    local_module_name = Enum.join(parent_pieces, ".")
    local_module_length = String.length(local_module_name)

    child_module
    |> String.slice(local_module_length..-1)
    |> strip_leading_period()
  end

  defp strip_leading_period(<<".", rest::binary>>), do: rest
  defp strip_leading_period(string_without_period), do: string_without_period

  defp immediate_descentent_defines_struct?(%Lexical.Project{} = project, module_name) do
    Intelligence.defines_struct?(project, module_name, to: :grandchild)
  end

  defp immediate_descendent_struct_modules(%Lexical.Project{} = project, module_name) do
    Intelligence.collect_struct_modules(project, module_name, to: :grandchild)
  end
end
