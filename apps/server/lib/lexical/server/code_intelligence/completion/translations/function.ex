defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Function do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.Function

  def translate(%Result.Function{} = function, _builder, %Env{} = env) do
    if Env.function_capture?(env) do
      function_capture_completions(function, env)
    else
      function_call_completion(function, env)
    end
  end

  defp function_capture_completions(%Result.Function{} = function, %Env{} = env) do
    name_and_arity = "#{function.name}/#{function.arity}"

    complete_capture =
      Env.plain_text(env, name_and_arity,
        label: "#{name_and_arity}",
        detail: "(Capture)",
        sort_text: "&" <> sort_text(function)
      )

    arg_templates = argument_templates(function, env)
    snippet_text = "#{function.name}(#{arg_templates})"
    args = Enum.join(function.argument_names, ", ")

    call_capture =
      Env.snippet(env, snippet_text,
        label: "#{function.name}(#{args})",
        detail: "(Capture with arguments)",
        sort_text: "&" <> sort_text(function)
      )

    [complete_capture, call_capture]
  end

  defp function_call_completion(%Result.Function{} = function, %Env{} = env) do
    label = "#{function.name}/#{function.arity}"
    arg_detail = Enum.join(function.argument_names, ",")
    detail = "#{function.origin}.#{label}(#{arg_detail})"
    add_args? = not String.contains?(env.suffix, "(")

    insert_text =
      if add_args? do
        arg_templates = argument_templates(function, env)

        "#{function.name}(#{arg_templates})"
      else
        "#{function.name}"
      end

    tags =
      if Map.get(function.metadata, :deprecated) do
        [:deprecated]
      end

    Env.snippet(env, insert_text,
      detail: detail,
      kind: :function,
      label: label,
      sort_text: sort_text(function),
      tags: tags
    )
  end

  defp argument_templates(%Result.Function{} = function, %Env{} = env) do
    argument_names =
      if Env.pipe?(env) do
        tl(function.argument_names)
      else
        function.argument_names
      end

    argument_names
    |> Enum.with_index()
    |> Enum.map_join(", ", fn {name, index} ->
      escaped_name = String.replace(name, "\\", "\\\\")
      "${#{index + 1}:#{escaped_name}}"
    end)
  end

  defp sort_text(%Result.Function{} = function) do
    normalized = String.replace(function.name, "__", "")
    "#{normalized}/#{function.arity}"
  end
end
