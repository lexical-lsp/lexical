defmodule Lexical.Server.CodeIntelligence.Completion do
  alias Future.Code, as: Code
  alias Lexical.Completion.Translatable
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Math
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Protocol.Types.InsertTextFormat
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translations.StructField
  alias Lexical.Server.Project.Intelligence

  require InsertTextFormat
  require Logger

  @lexical_deps Enum.map([:lexical | Mix.Project.deps_apps()], &Atom.to_string/1)

  @lexical_dep_modules Enum.map(@lexical_deps, &Macro.camelize/1)

  def trigger_characters do
    [".", "@", "&", "%", "^", ":", "!", "-", "~"]
  end

  @spec complete(Project.t(), Document.t(), Position.t(), Completion.Context.t()) :: [
          Completion.Item
        ]
  def complete(
        %Project{} = project,
        %Document{} = document,
        %Position{} = position,
        %Completion.Context{} = context
      ) do
    case Env.new(project, document, position) do
      {:ok, env} ->
        completions = completions(project, env, context)
        Logger.warning("Emitting completions: #{inspect(completions)}")
        completions

      {:error, _} = error ->
        Logger.error("Failed to build completion env #{inspect(error)}")
        empty_completion_list()
    end
  end

  defp completions(%Project{} = project, %Env{} = env, %Completion.Context{} = context) do
    prefix_tokens = Env.prefix_tokens(env, 1)

    cond do
      prefix_tokens == [] ->
        empty_completion_list()

      match?([{:operator, :do, _}], prefix_tokens) and Env.empty?(env.suffix) ->
        do_end_snippet = "do\n$0\nend"

        env
        |> Env.snippet(do_end_snippet, label: "do/end block")
        |> List.wrap()

      Enum.empty?(prefix_tokens) or not context_will_give_meaningful_completions?(env) ->
        Completion.List.new(items: [], is_incomplete: true)

      Env.in_context?(env, :struct_arguments) and not Env.in_context?(env, :value) and
          not prefix_is_trigger?(env) ->
        {line, column} = Env.prefix_alias_position(env)
        poisiton = Position.new(line, column)

        project
        |> RemoteControl.Api.complete_struct_fields(env.document, poisiton)
        |> StructField.translate(Env, env)

      true ->
        {document, position} = Env.strip_struct_reference(env)

        project
        |> RemoteControl.Api.complete(document, position)
        |> to_completion_items(project, env, context)
    end
  end

  defp prefix_is_trigger?(env) do
    case Env.prefix_tokens(env, 1) do
      [{_, token, _}] ->
        to_string(token) in trigger_characters()

      _ ->
        false
    end
  end

  defp to_completion_items(
         local_completions,
         %Project{} = project,
         %Env{} = env,
         %Completion.Context{} = context
       ) do
    Logger.info("Local completions are #{inspect(local_completions)}")

    for result <- local_completions,
        displayable?(project, result),
        applies_to_context?(project, result, context),
        applies_to_env?(env, result),
        %Completion.Item{} = item <- List.wrap(Translatable.translate(result, Env, env)) do
      item
    end
  end

  defp context_will_give_meaningful_completions?(%Env{} = env) do
    case Code.Fragment.cursor_context(env.prefix) do
      {:local_or_var, name} ->
        local_length = length(name)

        surround_begin =
          Math.clamp(env.position.character - local_length - 1, 1, env.position.character)

        case Code.Fragment.surround_context(env.prefix, {1, surround_begin}) do
          :none ->
            local_length > 1

          _other ->
            true
        end

      :none ->
        false

      {:unquoted_atom, name} ->
        length(name) > 1

      _ ->
        true
    end
  end

  defp displayable?(%Project{} = project, result) do
    # Don't exclude a dependency if we're working on that project!
    if Project.name(project) in @lexical_deps do
      true
    else
      suggested_module =
        case result do
          %_{full_name: full_name} -> full_name
          %_{origin: origin} -> origin
          _ -> ""
        end

      Enum.reduce_while(@lexical_dep_modules, true, fn module, _ ->
        if String.starts_with?(suggested_module, module) do
          {:halt, false}
        else
          {:cont, true}
        end
      end)
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp applies_to_env?(%Env{} = env, %struct_module{} = result) do
    struct_reference? = Env.in_context?(env, :struct_reference)

    cond do
      struct_reference? and struct_module == Candidate.Struct ->
        true

      struct_reference? and struct_module == Candidate.Module ->
        Intelligence.defines_struct?(env.project, result.full_name, to: :child)

      struct_reference? and match?(%Candidate.Macro{name: "__MODULE__"}, result) ->
        true

      struct_reference? ->
        false

      Env.in_context?(env, :bitstring) ->
        struct_module in [Candidate.BitstringOption, Candidate.Variable]

      Env.in_context?(env, :alias) ->
        struct_module in [
          Candidate.Behaviour,
          Candidate.Module,
          Candidate.Protocol,
          Candidate.Struct
        ]

      true ->
        true
    end
  end

  defp applies_to_context?(%Project{} = project, result, %Completion.Context{
         trigger_kind: :trigger_character,
         trigger_character: "%"
       }) do
    case result do
      %Candidate.Module{} = result ->
        Intelligence.defines_struct?(project, result.full_name, from: :child, to: :child)

      %Candidate.Struct{} ->
        true

      _other ->
        false
    end
  end

  defp applies_to_context?(_project, _result, _context) do
    true
  end

  defp empty_completion_list do
    Completion.List.new(items: [], is_incomplete: true)
  end
end
