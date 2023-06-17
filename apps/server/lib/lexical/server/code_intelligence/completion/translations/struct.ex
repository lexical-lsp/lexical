defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Struct do
  alias Future.Code, as: Code
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations

  use Translatable.Impl, for: Candidate.Struct

  def translate(%Candidate.Struct{} = struct, builder, %Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      completion(env, builder, struct.name, struct.full_name)
    else
      Translations.ModuleOrBehaviour.completion(
        env,
        builder,
        struct.name,
        struct.full_name
      )
    end
  end

  def completion(%Env{} = env, builder, module_name, full_name, more) when is_integer(more) do
    builder_opts = [
      kind: :module,
      label: "#{module_name}...(#{more} more structs)",
      detail: "#{full_name}."
    ]

    insert_text = "#{module_name}."
    range = edit_range(env)

    builder.text_edit_snippet(env, insert_text, range, builder_opts)
  end

  def completion(%Env{} = env, builder, struct_name, full_name) do
    builder_opts = [
      kind: :struct,
      detail: "#{full_name}",
      label: "#{struct_name}"
    ]

    range = edit_range(env)

    insert_text =
      if add_curlies?(env) do
        struct_name <> "{$1}"
      else
        struct_name
      end

    builder.text_edit_snippet(env, insert_text, range, builder_opts)
  end

  defp add_curlies?(%Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      not String.contains?(env.suffix, "{")
    else
      false
    end
  end

  defp edit_range(%Env{} = env) do
    prefix_end = env.position.character

    edit_begin =
      case Code.Fragment.cursor_context(env.prefix) do
        {:struct, {:dot, {:alias, _typed_module}, _rest}} ->
          prefix_end

        {:struct, typed_module_name} ->
          beginning_of_edit(env, typed_module_name)

        {:local_or_var, [?_ | _rest] = typed} ->
          beginning_of_edit(env, typed)
      end

    {edit_begin, env.position.character}
  end

  defp beginning_of_edit(env, typed_module_name) do
    case left_offset_of(typed_module_name, ?.) do
      {:ok, offset} ->
        env.position.character - offset

      :error ->
        env.position.character - length(typed_module_name)
    end
  end

  defp left_offset_of(string, character) do
    string
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce_while(:error, fn
      {^character, index}, _ ->
        {:halt, {:ok, index}}

      _, acc ->
        {:cont, acc}
    end)
  end
end
