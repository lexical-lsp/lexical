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
    name_and_arity = name_and_arity(function)

    complete_capture =
      Env.plain_text(env, name_and_arity,
        detail: "(Capture)",
        kind: :function,
        label: name_and_arity,
        sort_text: "&" <> sort_text(function)
      )

    call_capture =
      Env.snippet(env, function_snippet(function, env),
        detail: "(Capture with arguments)",
        kind: :function,
        label: function_label(function),
        sort_text: "&" <> sort_text(function)
      )

    [complete_capture, call_capture]
  end

  defp function_call_completion(%Result.Function{} = function, %Env{} = env) do
    add_args? = not String.contains?(env.suffix, "(")

    insert_text =
      if add_args? do
        function_snippet(function, env)
      else
        function.name
      end

    tags =
      if Map.get(function.metadata, :deprecated) do
        [:deprecated]
      end

    Env.snippet(env, insert_text,
      kind: :function,
      label: function_label(function),
      sort_text: sort_text(function),
      tags: tags
    )
  end

  defp function_snippet(%Result.Function{} = function, %Env{} = env) do
    argument_names =
      if Env.pipe?(env) do
        tl(function.argument_names)
      else
        function.argument_names
      end

    argument_templates =
      argument_names
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {name, index} ->
        escaped_name = String.replace(name, "\\", "\\\\")
        "${#{index + 1}:#{escaped_name}}"
      end)

    "#{function.name}(#{argument_templates})"
  end

  defp sort_text(%Result.Function{} = function) do
    normalized = String.replace(function.name, "__", "")
    "#{normalized}/#{function.arity}"
  end

  defp function_label(%Result.Function{} = function) do
    arg_detail = Enum.join(function.argument_names, ", ")
    "#{function.name}(#{arg_detail})"
  end

  defp name_and_arity(%Result.Function{} = function) do
    "#{function.name}/#{function.arity}"
  end
end
