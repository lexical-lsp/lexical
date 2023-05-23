defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Struct do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations

  use Translatable.Impl, for: Result.Struct

  def translate(%Result.Struct{} = struct, builder, %Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      completion(env, builder, struct.name)
    else
      Translations.ModuleOrBehaviour.completion(
        env,
        builder,
        struct.name
      )
    end
  end

  def completion(%Env{} = env, builder, struct_name) do
    builder_opts = [
      kind: :struct,
      detail: "#{struct_name} (Struct)",
      label: "%#{struct_name}"
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

  def add_curlies?(%Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      not String.contains?(env.suffix, "{")
    else
      false
    end
  end

  def add_percent?(%Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      # A leading percent is added only if the struct reference is to a top-level struct.
      # If it's for a child struct (e.g. %Types.Range) then adding a percent at "Range"
      # will be syntactically invalid and get us `%Types.%Range{}`

      struct_module_name =
        case Code.Fragment.cursor_context(env.prefix) do
          {:struct, {:dot, {:alias, module_name}, []}} ->
            '#{module_name}.'

          {:struct, module_name} ->
            module_name

          {:dot, {:alias, module_name}, _} ->
            module_name

          _ ->
            ''
        end

      contains_period? =
        struct_module_name
        |> List.to_string()
        |> String.contains?(".")

      not contains_period?
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
