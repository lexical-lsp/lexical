defmodule Lexical.Server.CodeIntelligence.Completion do
  alias Future.Code, as: Code
  alias Lexical.Ast.Env
  alias Lexical.Completion.Translatable
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Protocol.Types.InsertTextFormat
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.RemoteControl.Modules.Predicate
  alias Lexical.Server.CodeIntelligence.Completion.Builder
  alias Lexical.Server.Configuration
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
        Logger.info("Emitting completions: #{inspect(completions)}")
        completion_list(completions)

      {:error, _} = error ->
        Logger.error("Failed to build completion env #{inspect(error)}")
        completion_list()
    end
  end

  defp completions(%Project{} = project, %Env{} = env, %Completion.Context{} = context) do
    prefix_tokens = Env.prefix_tokens(env, 1)

    cond do
      prefix_tokens == [] or not should_emit_completions?(env) ->
        []

      should_emit_do_end_snippet?(env) ->
        do_end_snippet = "do\n  $0\nend"

        env
        |> Builder.snippet(do_end_snippet, label: "do/end block")
        |> List.wrap()

      Env.in_context?(env, :struct_field_key) ->
        project
        |> RemoteControl.Api.complete_struct_fields(env.document, env.position)
        |> Enum.map(&Translatable.translate(&1, Builder, env))

      true ->
        {stripped, position} = Builder.strip_struct_operator_for_elixir_sense(env)

        project
        |> RemoteControl.Api.complete(stripped, position)
        |> to_completion_items(project, env, context)
    end
  end

  defp should_emit_completions?(%Env{} = env) do
    always_emit_completions?() or has_meaningful_completions?(env)
  end

  defp always_emit_completions? do
    # If VS Code receives an empty completion list, it will never issue
    # a new request, even if `is_incomplete: true` is specified.
    # https://github.com/lexical-lsp/lexical/issues/400
    Configuration.get().client_name == "Visual Studio Code"
  end

  defp has_meaningful_completions?(%Env{} = env) do
    case Code.Fragment.cursor_context(env.prefix) do
      :none ->
        false

      {:unquoted_atom, name} ->
        length(name) > 1

      {:local_or_var, name} ->
        local_length = length(name)
        surround_begin = max(1, env.position.character - local_length - 1)

        local_length > 1 or has_surround_context?(env.prefix, 1, surround_begin)

      _ ->
        true
    end
  end

  defp has_surround_context?(fragment, line, column)
       when is_binary(fragment) and line >= 1 and column >= 1 do
    Code.Fragment.surround_context(fragment, {line, column}) != :none
  end

  # We emit a do/end snippet if the prefix token is the do operator and
  # there is a space before the token preceding it on the same line. This
  # handles situations like `@do|` where a do/end snippet would be invalid.
  defp should_emit_do_end_snippet?(%Env{} = env) do
    prefix_tokens = Env.prefix_tokens(env, 2)

    valid_prefix? =
      match?(
        [{:operator, :do, {line, do_col}}, {_, _, {line, preceding_col}}]
        when do_col - preceding_col > 1,
        prefix_tokens
      )

    valid_prefix? and Env.empty?(env.suffix)
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
        %Completion.Item{} = item <- to_completion_item(result, env) do
      item
    end
  end

  defp to_completion_item(candidate, env) do
    candidate
    |> Translatable.translate(Builder, env)
    |> List.wrap()
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
    Completion.List.new(items: items, is_incomplete: items == [])
  end
end
