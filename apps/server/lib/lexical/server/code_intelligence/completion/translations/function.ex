defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Function do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.Function

  def translate(%Result.Function{} = function, builder, %Env{} = env) do
    label = "#{function.name}/#{function.arity}"
    arg_detail = Enum.join(function.argument_names, ",")
    detail = "#{function.origin}.#{label}(#{arg_detail})"
    add_args? = not String.contains?(env.suffix, "(")

    insert_text =
      cond do
        function.arity == 1 and Env.function_capture?(env) ->
          "#{function.name}/1$0"

        add_args? ->
          argument_names =
            if Env.pipe?(env) do
              tl(function.argument_names)
            else
              function.argument_names
            end

          arg_templates =
            argument_names
            |> Enum.with_index()
            |> Enum.map_join(", ", fn {name, index} ->
              escaped_name = String.replace(name, "\\", "\\\\")
              "${#{index + 1}:#{escaped_name}}"
            end)

          "#{function.name}(#{arg_templates})$0"

        true ->
          "#{function.name}$0"
      end

    sort_text = String.replace(label, "__", "")

    tags =
      if Map.get(function.metadata, :deprecated) do
        [:deprecated]
      end

    builder.snippet(env, insert_text,
      detail: detail,
      kind: :function,
      label: label,
      sort_text: sort_text,
      tags: tags
    )
  end
end
