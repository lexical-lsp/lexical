defmodule Lexical.Server.CodeIntelligence.Completion do
  alias Future.Code, as: Code
  alias Lexical.Ast.Env
  alias Lexical.Completion.Translatable
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Math
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Protocol.Types.InsertTextFormat
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.RemoteControl.Modules.Predicate
  alias Lexical.Server.CodeIntelligence.Completion.Builder
  alias Lexical.Server.Project.Intelligence
  alias Mix.Tasks.Namespace

  use Predicate.Syntax
  require InsertTextFormat
  require Logger

  @lexical_deps Enum.map([:lexical | Mix.Project.deps_apps()], &Atom.to_string/1)

  @lexical_dep_modules Enum.map(@lexical_deps, &Macro.camelize/1)

  def trigger_characters do
    [".", "@", "&", "%", "^", ":", "!", "-", "~"]
  end

  @spec complete(Project.t(), Document.t(), Position.t(), Completion.Context.t()) ::
          Completion.List.t()
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
        completion_list(completions)

      {:error, _} = error ->
        Logger.error("Failed to build completion env #{inspect(error)}")
        completion_list()
    end
  end

  defp completions(%Project{} = project, %Env{} = env, %Completion.Context{} = context) do
    prefix_tokens = Env.prefix_tokens(env, 1)

    cond do
      prefix_tokens == [] ->
        []

      match?([{:operator, :do, _}], prefix_tokens) and Env.empty?(env.suffix) ->
        do_end_snippet = "do\n  $0\nend"

        env
        |> Builder.snippet(do_end_snippet, label: "do/end block")
        |> List.wrap()

      Enum.empty?(prefix_tokens) or not context_will_give_meaningful_completions?(env) ->
        []

      Env.in_context?(env, :struct_arguments) and not Env.in_context?(env, :struct_field_value) and
          not prefix_is_trigger?(env) ->
        project
        |> RemoteControl.Api.complete_struct_fields(env.document, env.position)
        |> Enum.map(&Translatable.translate(&1, Builder, env))

      true ->
        {document, position} = Builder.strip_struct_reference(env)

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
        %Completion.Item{} = item <- List.wrap(Translatable.translate(result, Builder, env)) do
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
    suggested_module =
      case result do
        %_{full_name: full_name} -> full_name
        %_{origin: origin} -> origin
        _ -> ""
      end

    cond do
      Namespace.Module.prefixed?(suggested_module) ->
        false

      # If we're working on the dependency, we should include it!
      Project.name(project) in @lexical_deps ->
        true

      true ->
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

      Env.in_context?(env, :use) ->
        case result do
          %{full_name: full_name} ->
            with_prefix =
              RemoteControl.Api.modules_with_prefix(
                env.project,
                full_name,
                predicate(&macro_exported?(&1, :__using__, 1))
              )

            not Enum.empty?(with_prefix)

          _ ->
            false
        end

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

  defp completion_list(items \\ []) do
    Completion.List.new(items: items, is_incomplete: true)
  end
end
