defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleOrBehaviour do
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations
  alias Lexical.Server.Project.Intelligence

  use Translatable.Impl,
    for: [Candidate.Module, Candidate.Struct, Candidate.Behaviour, Candidate.Protocol]

  def translate(%Candidate.Module{} = module, builder, %Env{} = env) do
    do_translate(module, builder, env)
  end

  def translate(%Candidate.Struct{} = module, builder, %Env{} = env) do
    do_translate(module, builder, env)
  end

  def translate(%Candidate.Behaviour{} = behaviour, builder, %Env{} = env) do
    do_translate(behaviour, builder, env)
  end

  def translate(%Candidate.Protocol{} = protocol, builder, %Env{} = env) do
    do_translate(protocol, builder, env)
  end

  defp do_translate(%_{} = module, builder, %Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      complete_in_struct_reference(env, builder, module)
    else
      detail = builder.fallback(module.summary, module.full_name)
      completion(env, builder, module.name, detail)
    end
  end

  defp complete_in_struct_reference(%Env{} = env, builder, %Candidate.Struct{} = struct) do
    immediate_descendent_structs =
      immediate_descendent_struct_modules(env.project, struct.full_name)

    if Enum.empty?(immediate_descendent_structs) do
      Translations.Struct.completion(env, builder, struct.name, struct.full_name)
    else
      do_complete_in_struct_reference(env, builder, struct, immediate_descendent_structs)
    end
  end

  defp complete_in_struct_reference(%Env{} = env, builder, %Candidate.Module{} = module) do
    immediate_descendent_structs =
      immediate_descendent_struct_modules(env.project, module.full_name)

    do_complete_in_struct_reference(env, builder, module, immediate_descendent_structs)
  end

  defp do_complete_in_struct_reference(
         %Env{} = env,
         builder,
         module_or_struct,
         immediate_descendent_structs
       ) do
    structs_map =
      Map.new(immediate_descendent_structs, fn module_or_struct -> {module_or_struct, true} end)

    dot_counts = module_dot_counts(module_or_struct.full_name)
    ancestors = ancestors(immediate_descendent_structs, dot_counts)

    Enum.flat_map(ancestors, fn ancestor ->
      local_name = local_module_name(module_or_struct.full_name, ancestor, module_or_struct.name)

      more =
        env.project
        |> Intelligence.collect_struct_modules(ancestor, to: :infinity)
        |> Enum.count()

      if struct?(ancestor, structs_map) do
        [
          Translations.Struct.completion(env, builder, local_name, ancestor),
          Translations.Struct.completion(env, builder, local_name, ancestor, more - 1)
        ]
      else
        [Translations.Struct.completion(env, builder, local_name, ancestor, more)]
      end
    end)
  end

  defp struct?(module, structs_map) do
    Map.has_key?(structs_map, module)
  end

  defp ancestors(results, dot_counts) do
    results
    |> Enum.map(fn module ->
      module |> String.split(".") |> Enum.take(dot_counts + 1) |> Enum.join(".")
    end)
    |> Enum.uniq()
  end

  defp module_dot_counts(module_name) do
    module_name |> String.graphemes() |> Enum.count(&(&1 == "."))
  end

  def completion(%Env{} = env, builder, module_name, detail \\ nil) do
    detail = builder.fallback(detail, "#{module_name} (Module)")

    env
    |> builder.plain_text(module_name, label: module_name, kind: :module, detail: detail)
    |> builder.boost(0, 2)
  end

  defp local_module_name(parent_module, child_module, aliased_module) do
    # Returns the "local" module name, so if you're completing
    # Types.Som and the module completion is "Types.Something.Else",
    # "Something.Else" is returned.

    parent_pieces = String.split(parent_module, ".")
    parent_pieces = Enum.take(parent_pieces, length(parent_pieces) - 1)
    local_module_name = Enum.join(parent_pieces, ".")
    local_module_length = String.length(local_module_name)

    local_name =
      child_module
      |> String.slice(local_module_length..-1)
      |> strip_leading_period()

    if String.starts_with?(local_name, aliased_module) do
      local_name
    else
      [_ | tail] = String.split(local_name, ".")
      Enum.join([aliased_module | tail], ".")
    end
  end

  defp strip_leading_period(<<".", rest::binary>>), do: rest
  defp strip_leading_period(string_without_period), do: string_without_period

  defp immediate_descendent_struct_modules(%Lexical.Project{} = project, module_name) do
    Intelligence.collect_struct_modules(project, module_name, to: :grandchild)
  end
end
