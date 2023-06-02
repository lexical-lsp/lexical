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

    immediate_descendent_structs =
      immediate_descendent_struct_modules(env.project, module.full_name)

    defines_struct_in_descendents? =
      immediate_descendent_defines_struct?(env.project, module.full_name) and
        length(immediate_descendent_structs) > 1

    cond do
      struct_reference? and defines_struct_in_descendents? and defines_struct? ->
        more = length(immediate_descendent_structs) - 1

        [
          Translations.Struct.completion(env, builder, module.name, module.full_name, more),
          Translations.Struct.completion(env, builder, module.name, module.full_name)
        ]

      struct_reference? and defines_struct? ->
        Translations.Struct.completion(env, builder, module.name, module.full_name)

      struct_reference? and
          immediate_descendent_defines_struct?(env.project, module.full_name) ->
        Enum.map(immediate_descendent_structs, fn child_module_name ->
          local_name = local_module_name(module.full_name, child_module_name)
          Translations.Struct.completion(env, builder, local_name, child_module_name)
        end)

      true ->
        detail = builder.fallback(module.summary, module.name)
        completion(env, builder, module.name, detail)
    end
  end

  def completion(%Env{} = env, builder, module_name, detail \\ nil) do
    detail = builder.fallback(detail, "#{module_name} (Module)")

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

  defp immediate_descendent_defines_struct?(%Lexical.Project{} = project, module_name) do
    Intelligence.defines_struct?(project, module_name, to: :grandchild)
  end

  defp immediate_descendent_struct_modules(%Lexical.Project{} = project, module_name) do
    Intelligence.collect_struct_modules(project, module_name, to: :grandchild)
  end
end
