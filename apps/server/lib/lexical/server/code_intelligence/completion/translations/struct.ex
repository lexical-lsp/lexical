defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Struct do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations
  alias Lexical.Protocol.Types.Markup.Content

  use Translatable.Impl, for: Result.Struct
  require Logger

  def translate(%Result.Struct{} = struct, builder, %Env{} = env) do
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
      label: "#{struct_name}",
      documentation: documentation(env.project, full_name)
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

  defp documentation(project, full_name) do
    project |> Api.struct_doc(full_name) |> to_markup()
  end

  defp to_markup(doc) do
    value = """

    ```elixir
    #{doc}
    ```
    """

    Content.new(kind: :markdown, value: value)
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
          edit_begin =
            case left_offset_of(typed_module_name, ?.) do
              {:ok, offset} ->
                env.position.character - offset

              :error ->
                env.position.character - length(typed_module_name)
            end

          edit_begin
      end

    {edit_begin, env.position.character}
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
