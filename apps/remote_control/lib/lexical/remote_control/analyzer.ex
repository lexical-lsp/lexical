defmodule Lexical.RemoteControl.Analyzer do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Require
  alias Lexical.Ast.Analysis.Use
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.Analyzer.Aliases
  alias Lexical.RemoteControl.Analyzer.Imports
  alias Lexical.RemoteControl.Analyzer.Requires
  alias Lexical.RemoteControl.Analyzer.Uses

  require Logger

  defdelegate aliases_at(analysis, position), to: Aliases, as: :at
  defdelegate imports_at(analysis, position), to: Imports, as: :at

  @spec requires_at(Analysis.t(), Position.t()) :: [module()]
  def requires_at(%Analysis{} = analysis, %Position{} = position) do
    analysis
    |> Requires.at(position)
    |> Enum.reduce([], fn %Require{} = require, acc ->
      case expand_alias(require.module, analysis, position) do
        {:ok, expanded} -> [expanded | acc]
        _ -> [Module.concat(require.as) | acc]
      end
    end)
  end

  @spec uses_at(Analysis.t(), Position.t()) :: [module()]
  def uses_at(%Analysis{} = analysis, %Position{} = position) do
    analysis
    |> Uses.at(position)
    |> Enum.reduce([], fn %Use{} = use, acc ->
      case expand_alias(use.module, analysis, position) do
        {:ok, expanded} -> [expanded | acc]
        _ -> [Module.concat(use.module) | acc]
      end
    end)
  end

  def resolve_local_call(%Analysis{} = analysis, %Position{} = position, function_name, arity) do
    maybe_imported_mfa =
      analysis
      |> imports_at(position)
      |> Enum.find(fn
        {_, ^function_name, ^arity} -> true
        _ -> false
      end)

    if is_nil(maybe_imported_mfa) do
      aliases = aliases_at(analysis, position)
      current_module = aliases[:__MODULE__]
      {current_module, function_name, arity}
    else
      maybe_imported_mfa
    end
  end

  @doc """
  Expands an alias at the given position in the context of a document
  analysis.

  When we refer to a module, it's usually a short name, often aliased or
  in a nested module. This function finds the full name of the module at
  a cursor position.

  For example, if we have:

      defmodule Project do
        defmodule Issue do
          defstruct [:message]
        end

        def message(%Issue{|} = issue) do # cursor marked as `|`
        end
      end

  We could get the expansion for the `Issue` alias at the cursor position
  like so:

      iex> Analyzer.expand_alias([:Issue], analysis, position)
      {:ok, Project.Issue}

  Another example:

      defmodule Project do
        defmodule Issue do
          defstruct [:message]
        end
      end

      defmodule MyModule do
        alias Project, as: MyProject

        def message(%MyProject.Issue{|} = issue) do
        end
      end

  This would yield the same result:

      iex> Analyzer.expand_alias([:MyProject, :Issue], analysis, position)
      {:ok, Project.Issue}

  If no aliases are present at the given position, no expansion occurs:

      iex> Analyzer.expand_alias([:Some, :Other, :Module], analysis, position)
      {:ok, Some.Other.Module}

  """
  @spec expand_alias(
          Ast.alias_segments() | module(),
          Analysis.t(),
          Position.t() | {Position.line(), Position.character()}
        ) ::
          {:ok, module()} | :error
  def expand_alias([_ | _] = segments, %Analysis{} = analysis, %Position{} = position) do
    with %Analysis{valid?: true} = analysis <- Lexical.Ast.reanalyze_to(analysis, position),
         aliases <- aliases_at(analysis, position),
         {:ok, resolved} <- resolve_alias(segments, aliases) do
      {:ok, Module.concat(resolved)}
    else
      _ ->
        case segments do
          [:__MODULE__] ->
            # we've had a request for the current module, but none was found
            # so we've failed. This can happen if we're resolving the current
            # module in a script, or inside the defmodule call.
            :error

          _ ->
            if Enum.all?(segments, &is_atom/1) do
              {:ok, Module.concat(segments)}
            else
              :error
            end
        end
    end
  end

  def expand_alias(module, %Analysis{} = analysis, %Position{} = position)
      when is_atom(module) and not is_nil(module) do
    {:elixir, segments} = Ast.Module.safe_split(module, as: :atoms)
    expand_alias(segments, analysis, position)
  end

  def expand_alias(empty, _, _) when empty in [nil, []] do
    Logger.warning("nothing to expand (expand_alias was passed #{inspect(empty)})")
    :error
  end

  @doc """
  Returns the current module at the given position in the analysis
  """
  def current_module(%Analysis{} = analysis, %Position{} = position) do
    expand_alias([:__MODULE__], analysis, position)
  end

  defp resolve_alias([{:@, _, [{:protocol, _, _}]} | rest], alias_mapping) do
    with {:ok, protocol} <- Map.fetch(alias_mapping, :"@protocol") do
      Ast.reify_alias(protocol, rest)
    end
  end

  defp resolve_alias(
         [{:__aliases__, _, [{:@, _, [{:protocol, _, _}]} | _] = protocol}],
         alias_mapping
       ) do
    resolve_alias(protocol, alias_mapping)
  end

  defp resolve_alias([{:@, _, [{:for, _, _} | _]} | rest], alias_mapping) do
    with {:ok, protocol_for} <- Map.fetch(alias_mapping, :"@for") do
      Ast.reify_alias(protocol_for, rest)
    end
  end

  defp resolve_alias(
         [{:__aliases__, _, [{:@, _, [{:for, _, _}]} | _] = protocol_for}],
         alias_mapping
       ) do
    resolve_alias(protocol_for, alias_mapping)
  end

  defp resolve_alias([first | _] = segments, aliases_mapping) when is_tuple(first) do
    with {:ok, current_module} <- Map.fetch(aliases_mapping, :__MODULE__) do
      Ast.reify_alias(current_module, segments)
    end
  end

  defp resolve_alias([first | _] = segments, aliases_mapping) when is_atom(first) do
    with :error <- fetch_leading_alias(segments, aliases_mapping) do
      fetch_trailing_alias(segments, aliases_mapping)
    end
  end

  defp resolve_alias(_, _), do: :error

  defp fetch_leading_alias([first | rest], aliases_mapping) do
    with {:ok, resolved} <- Map.fetch(aliases_mapping, first) do
      {:ok, [resolved | rest]}
    end
  end

  defp fetch_trailing_alias(segments, aliases_mapping) do
    # Trailing aliases happen when you use the curly syntax to define multiple aliases
    # in one go, like Foo.{First, Second.Third, Fourth}
    # Our alias mapping will have Third mapped to Foo.Second.Third, so we need to look
    # for Third, wheras the leading alias will look for Second in the mappings.
    with {:ok, resolved} <- Map.fetch(aliases_mapping, List.last(segments)) do
      {:ok, List.wrap(resolved)}
    end
  end
end
