defmodule Lexical.RemoteControl.CodeAction.Handlers.AddAlias do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Alias
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Formats
  alias Lexical.RemoteControl.Analyzer
  alias Lexical.RemoteControl.CodeAction
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.CodeMod
  alias Lexical.RemoteControl.Modules
  alias Lexical.RemoteControl.Search
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Sourceror.Zipper

  require Logger
  @behaviour CodeAction.Handler

  @impl CodeAction.Handler
  def actions(%Document{} = doc, %Range{} = range, _diagnostics) do
    with {:ok, _doc, %Analysis{valid?: true} = analysis} <-
           Document.Store.fetch(doc.uri, :analysis),
         {:ok, resolved, _} <- Entity.resolve(analysis, range.start),
         {:ok, unaliased_module} <- fetch_unaliased_module(analysis, range.start, resolved) do
      current_aliases = CodeMod.Aliases.in_scope(analysis, range)

      unaliased_module
      |> possible_aliases()
      |> filter_by_resolution(resolved)
      |> Enum.map(&build_code_action(analysis, range, current_aliases, &1))
    else
      _ ->
        []
    end
  end

  @impl CodeAction.Handler
  def kinds do
    [:quick_fix]
  end

  defp build_code_action(%Analysis{} = analysis, range, current_aliases, potential_alias_module) do
    {insert_position, trailer} = insert_position_and_trailer(current_aliases, analysis, range)
    split_alias = potential_alias_module |> Module.split() |> Enum.map(&String.to_atom/1)
    alias_to_add = %Alias{module: split_alias, as: List.last(split_alias), explicit?: true}
    replace_current_alias = get_current_replacement(analysis, range, split_alias)

    alias_edits =
      CodeMod.Aliases.to_edits(
        [alias_to_add | current_aliases],
        insert_position,
        trailer
      )

    changes = Changes.new(analysis.document, replace_current_alias ++ alias_edits)

    CodeAction.new(
      analysis.document.uri,
      "alias #{Formats.module(potential_alias_module)}",
      :quick_fix,
      changes
    )
  end

  def fetch_unaliased_module(%Analysis{} = analysis, %Position{} = position, resolved) do
    with {:ok, module} <- fetch_module(resolved),
         %{} = aliases <- Analyzer.aliases_at(analysis, position),
         false <- module in Map.values(aliases) do
      {:ok, module}
    else
      _ ->
        :error
    end
  end

  defp fetch_module({:module, module}), do: {:ok, module}
  defp fetch_module({:struct, module}), do: {:ok, module}
  defp fetch_module({:call, module, _function, _arity}), do: {:ok, module}
  defp fetch_module(_), do: :error

  defp get_current_replacement(%Analysis{} = analysis, %Range{} = range, split_alias) do
    with {:ok, patches} <- replace_full_module_on_line(analysis, range.start.line, split_alias),
         {:ok, edits} <- Ast.patches_to_edits(analysis.document, patches) do
      edits
    else
      _ ->
        []
    end
  end

  defp replace_full_module_on_line(%Analysis{} = analysis, line, split_alias) do
    aliased_module =
      split_alias
      |> List.last()
      |> List.wrap()
      |> Module.concat()
      |> Formats.module()

    analysis.document
    |> Ast.traverse_line(line, [], fn
      %Zipper{node: {:__aliases__, _, ^split_alias}} = zipper, patches ->
        range = Sourceror.get_range(zipper.node)

        patch = %{range: range, change: aliased_module}
        {zipper, [patch | patches]}

      zipper, acc ->
        {zipper, acc}
    end)
    |> case do
      {:ok, _, patches} -> {:ok, patches}
      error -> error
    end
  end

  @similarity_threshold 0.75
  defp similar?(a, b), do: String.jaro_distance(a, b) >= @similarity_threshold

  defp filter_by_resolution(modules_stream, {:call, _module, function, _arity}) do
    query_function = Atom.to_string(function)

    Stream.filter(modules_stream, fn module ->
      case Modules.fetch_functions(module) do
        {:ok, functions} ->
          Enum.any?(functions, fn {name, _arity} ->
            module_function = Atom.to_string(name)
            similar?(module_function, query_function)
          end)

        _ ->
          false
      end
    end)
  end

  defp filter_by_resolution(modules_stream, {:struct, _}) do
    Stream.filter(modules_stream, fn module ->
      case Modules.fetch_functions(module) do
        {:ok, functions} -> Keyword.has_key?(functions, :__struct__)
        _ -> false
      end
    end)
  end

  defp filter_by_resolution(modules_stream, _) do
    modules_stream
  end

  defp possible_aliases(unaliased_module) do
    unaliased_strings = Module.split(unaliased_module)

    unaliased_module
    |> Formats.module()
    |> Search.Store.fuzzy(type: :module, subtype: :definition)
    |> Stream.uniq_by(& &1.subject)
    |> Stream.filter(fn %Entry{} = entry ->
      split = Module.split(entry.subject)

      head_module = split |> List.first() |> List.wrap() |> Module.concat()
      tail_module = split |> List.last()

      protocol? = function_exported?(head_module, :__protocol__, 1)

      if protocol? do
        false
      else
        Enum.any?(unaliased_strings, &similar?(&1, tail_module))
      end
    end)
    |> Stream.map(& &1.subject)
  end

  defp insert_position_and_trailer([%Alias{} = first | _], _, _) do
    {first.range.start, nil}
  end

  defp insert_position_and_trailer([], %Analysis{} = analysis, range) do
    case Analysis.module_scope(analysis, range) do
      %Scope{id: :global} = scope ->
        {scope.range.start, "\n"}

      %Scope{} = scope ->
        start_pos = scope.range.start
        # we use the end position here because the start position is right after
        # the do for modules, which puts it well into the line. The end position
        # is before the end, which is equal to the indent of the scope.
        end_pos = scope.range.end

        start_pos =
          start_pos
          |> put_in([:line], start_pos.line + 1)
          |> put_in([:character], end_pos.character + 2)

        {start_pos, "\n"}
    end
  end
end
