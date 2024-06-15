defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Callable do
  alias Lexical.Ast
  alias Lexical.Ast.Env
  alias Lexical.Completion.SortScope
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Builder

  @callables [Candidate.Function, Candidate.Macro, Candidate.Callback, Candidate.Typespec]

  @syntax_macros ~w(= == == === =~ .. ..// ! != !== &&)

  def completion(%_callable_module{name: name}, _env)
      when name in @syntax_macros do
    :skip
  end

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

  # for a callable to be local, it must be defined in the current scope,
  # or be a callback.
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

    kind =
      case callable do
        %Candidate.Typespec{} ->
          :type_parameter

        _ ->
          :function
      end

    detail =
      if callback?(callable) do
        "(callback)"
      else
        "(#{callable.type})"
      end

    env
    |> Builder.snippet(insert_text,
      label: label(callable, env),
      kind: kind,
      detail: detail,
      sort_text: sort_text(callable),
      filter_text: "#{callable.name}",
      documentation: build_docs(callable),
      tags: tags
    )
    |> set_sort_scope(callable, env)
  end

  def capture_completions(%callable_module{} = callable, %Env{} = env)
      when callable_module in @callables do
    name_and_arity = name_and_arity(callable)

    local_priority =
      if capture_arity_matches?(callable.arity, env) do
        0
      else
        1
      end

    complete_capture =
      env
      |> Builder.plain_text(name_and_arity,
        label: name_and_arity,
        kind: :function,
        detail: "(Capture)",
        sort_text: sort_text(callable, "0"),
        filter_text: "#{callable.name}",
        documentation: build_docs(callable)
      )
      |> set_sort_scope(callable, env, local_priority)

    call_capture =
      env
      |> Builder.snippet(callable_snippet(callable, env),
        label: label(callable, env),
        kind: :function,
        detail: "(Capture with arguments)",
        sort_text: sort_text(callable, "1"),
        filter_text: "#{callable.name}",
        documentation: build_docs(callable)
      )
      |> set_sort_scope(callable, env, local_priority)

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

    if callable.parens? do
      "#{callable.name}(#{argument_templates})"
    else
      "#{callable.name} #{argument_templates}"
    end
  end

  @default_functions ["module_info", "behaviour_info"]

  defp set_sort_scope(item, callable, %Env{} = env, default_local_priority \\ 1) do
    position_module = env.position_module

    %_{
      name: name,
      origin: origin,
      metadata: metadata
    } = callable

    # elixir_sense suggests child_spec as a callback, though it's not formally one.
    deprecated? = Map.has_key?(metadata, :deprecated)
    dunder? = String.starts_with?(name, "__")
    callback? = callback?(callable)

    local_priority =
      cond do
        dunder? -> 9
        callback? -> 8
        true -> default_local_priority
      end

    cond do
      origin === "Kernel" or origin === "Kernel.SpecialForms" or name in @default_functions ->
        Builder.set_sort_scope(item, SortScope.global(deprecated?, local_priority))

      origin === position_module ->
        Builder.set_sort_scope(item, SortScope.local(deprecated?, local_priority))

      true ->
        Builder.set_sort_scope(item, SortScope.remote(deprecated?, local_priority))
    end
  end

  defp label(%_{} = callable, env) do
    arg_detail = callable |> argument_names(env) |> Enum.join(", ")

    if callable.parens? do
      "#{callable.name}(#{arg_detail})"
    else
      "#{callable.name} #{arg_detail}"
    end
  end

  defp name_and_arity(%_{name: name, arity: arity}) do
    "#{name}/#{arity}"
  end

  defp sort_text(%_callable{name: name, arity: arity}, suffix \\ "") do
    normalized_arity =
      arity
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    # we used to use : as a separator between the name and
    # arity, but this  caused bang functions to sort
    # before non-bang variants, which is incorrect.
    # Using a space sorts correctly, as it's the only ascii
    # character lower than bang

    "#{name} #{normalized_arity}#{suffix}"
  end

  defp build_docs(%{summary: summary, spec: spec})
       when is_binary(summary) and is_binary(spec) do
    "#{summary}\n```elixir\n#{spec}\n```"
  end

  defp build_docs(%{summary: summary}) when is_binary(summary) do
    summary
  end

  defp build_docs(%{spec: spec}) when is_binary(spec) do
    "```elixir\n#{spec}\n```"
  end

  defp build_docs(_) do
    ""
  end

  defp callback?(%_{name: name, metadata: metadata} = _callable) do
    Map.has_key?(metadata, :implementing) || name === "child_spec"
  end

  defp capture_arity_matches?(arity, %Env{} = env) when is_integer(arity) do
    case Ast.path_at(env.analysis, env.position) do
      {:ok, path} ->
        slash_arity_path?(path, arity) || arg_arity_path?(path, arity)

      _ ->
        false
    end
  end

  # &fun|/2
  defp slash_arity_path?(
         [
           fun,
           {:/, _, [fun, {:__block__, _, [arity]}]} = slash_arity,
           {:&, _, [slash_arity]}
           | _
         ],
         arity
       ) do
    true
  end

  # &Mod.fun|/2
  defp slash_arity_path?(
         [
           {:., _, _} = dot_fun,
           {dot_fun, _, _} = dot_fun_call,
           {:/, _, [dot_fun_call, {:__block__, _, [arity]}]} = slash_arity,
           {:&, _, [slash_arity]}
           | _
         ],
         arity
       ) do
    true
  end

  defp slash_arity_path?(_path, _arity), do: false

  # fun|(x, y)
  defp arg_arity_path?(
         [
           {atom, _, args} = call,
           {:&, _, [call]}
           | _
         ],
         arity
       )
       when is_atom(atom) and is_list(args) do
    length(args) == arity
  end

  # Mod.fun|(x, y)
  defp arg_arity_path?(
         [
           {:., _, _} = dot_fun,
           {dot_fun, _, args} = call,
           {:&, _, [call]}
           | _
         ],
         arity
       )
       when is_list(args) do
    length(args) == arity
  end

  defp arg_arity_path?(_path, _arity), do: false
end
