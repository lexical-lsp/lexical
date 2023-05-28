defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Callable do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env

  @callables [Result.Function, Result.Macro]

  def completion(%callable_module{argument_names: []} = callable, %Env{} = env)
      when callable_module in @callables do
    if not Env.in_context?(env, :pipe) do
      do_completion(callable, env)
    end
  end

  def completion(%callable_module{} = callable, %Env{} = env)
      when callable_module in @callables do
    do_completion(callable, env)
  end

  defp do_completion(callable, %Env{} = env) do
    add_args? = not String.contains?(env.suffix, "(")

    insert_text =
      if add_args? do
        callable_snippet(callable, env)
      else
        callable.name
      end

    tags =
      if Map.get(callable.metadata, :deprecated) do
        [:deprecated]
      end

    Env.snippet(env, insert_text,
      kind: :function,
      label: label(callable),
      sort_text: sort_text(callable),
      tags: tags
    )
  end

  def capture_completions(%callable_module{} = callable, %Env{} = env)
      when callable_module in @callables do
    name_and_arity = name_and_arity(callable)

    complete_capture =
      Env.plain_text(env, name_and_arity,
        detail: "(Capture)",
        kind: :function,
        label: name_and_arity,
        sort_text: "&" <> sort_text(callable)
      )

    call_capture =
      Env.snippet(env, callable_snippet(callable, env),
        detail: "(Capture with arguments)",
        kind: :function,
        label: label(callable),
        sort_text: "&" <> sort_text(callable)
      )

    [complete_capture, call_capture]
  end

  defp callable_snippet(%_{} = callable, %Env{} = env) do
    argument_names =
      if Env.in_context?(env, :pipe) do
        tl(callable.argument_names)
      else
        callable.argument_names
      end

    argument_templates =
      argument_names
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {name, index} ->
        "${#{index}:#{name}}"
      end)

    "#{callable.name}(#{argument_templates})"
  end

  defp sort_text(%_{name: name, arity: arity}) do
    normalized = String.replace(name, "__", "")
    "#{normalized}/#{arity}"
  end

  defp label(%_{name: name, argument_names: argument_names}) do
    arg_detail = Enum.join(argument_names, ", ")
    "#{name}(#{arg_detail})"
  end

  defp name_and_arity(%_{name: name, arity: arity}) do
    "#{name}/#{arity}"
  end
end
