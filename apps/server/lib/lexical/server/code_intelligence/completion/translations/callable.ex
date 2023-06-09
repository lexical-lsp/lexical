defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Callable do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env

  @callables [Result.Function, Result.Macro, Result.Callback]

  def completion(%callable_module{arity: 0} = callable, %Env{} = env)
      when callable_module in @callables do
    unless Env.in_context?(env, :pipe) do
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

    env
    |> Env.snippet(insert_text,
      kind: :function,
      label: label(callable, env),
      tags: tags
    )
    |> maybe_boost(callable)
  end

  def capture_completions(%callable_module{} = callable, %Env{} = env)
      when callable_module in @callables do
    name_and_arity = name_and_arity(callable)

    complete_capture =
      env
      |> Env.plain_text(name_and_arity,
        detail: "(Capture)",
        kind: :function,
        label: name_and_arity
      )
      |> maybe_boost(callable, 4)

    call_capture =
      env
      |> Env.snippet(callable_snippet(callable, env),
        detail: "(Capture with arguments)",
        kind: :function,
        label: label(callable, env)
      )
      |> maybe_boost(callable, 4)

    [complete_capture, call_capture]
  end

  defp argument_names(%_{arity: 0}, _env) do
    []
  end

  defp argument_names(%_{} = callable, %Env{} = env) do
    if Env.in_context?(env, :pipe) do
      tl(callable.argument_names)
    else
      callable.argument_names
    end
  end

  defp callable_snippet(%_{} = callable, env) do
    argument_templates =
      callable
      |> argument_names(env)
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {name, index} ->
        "${#{index}:#{name}}"
      end)

    "#{callable.name}(#{argument_templates})"
  end

  @default_functions ["module_info", "behaviour_info"]

  defp maybe_boost(item, %_{name: name}, default_boost \\ 5) do
    if String.starts_with?(name, "__") or name in @default_functions do
      item
    else
      Env.boost(item, default_boost)
    end
  end

  defp label(%_{} = callable, env) do
    arg_detail = callable |> argument_names(env) |> Enum.join(", ")
    "#{callable.name}(#{arg_detail})"
  end

  defp name_and_arity(%_{name: name, arity: arity}) do
    "#{name}/#{arity}"
  end
end
