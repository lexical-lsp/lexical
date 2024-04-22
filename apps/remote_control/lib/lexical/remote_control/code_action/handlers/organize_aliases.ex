defmodule Lexical.RemoteControl.CodeAction.Handlers.OrganizeAliases do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Alias
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.CodeAction

  require Logger

  @behaviour CodeAction.Handler

  @impl CodeAction.Handler
  def actions(%Document{} = doc, %Range{} = range, _diagnostics) do
    with {:ok, _doc, analysis} <- Document.Store.fetch(doc.uri, :analysis),
         :ok <- check_aliases(doc, analysis, range) do
      edits =
        analysis
        |> Analysis.scopes_at(range.start)
        |> enclosing_scopes(range)
        |> narrorwest_scope(range.start)
        |> aliases_in_scope()
        |> aliases_to_edits()

      if Enum.empty?(edits) do
        []
      else
        changes = Changes.new(doc, edits)
        [CodeAction.new(doc.uri, "Organize aliases", :source, changes)]
      end
    else
      _ ->
        []
    end
  end

  @impl CodeAction.Handler
  def kinds do
    [:source_organize_imports]
  end

  defp aliases_to_edits([]), do: []

  defp aliases_to_edits(aliases) do
    first_alias_start = first_alias_range(aliases).start
    initial_spaces = first_alias_start.character - 1

    alias_text =
      aliases
      # get rid of duplicate aliases
      |> Enum.uniq_by(& &1.module)
      |> Enum.map_join("\n", fn %Alias{} = a ->
        text =
          if List.last(a.module) == a.as do
            "alias #{join(a.module)}"
          else
            "alias #{join(a.module)}, as: #{join(List.wrap(a.as))}"
          end

        indent(text, initial_spaces)
      end)
      |> String.trim_trailing()

    zeroed_start = %Position{first_alias_start | character: 1}
    new_alias_range = Range.new(zeroed_start, zeroed_start)
    edits = remove_old_aliases(aliases)

    edits ++
      [Edit.new(alias_text, new_alias_range)]
  end

  defp remove_old_aliases(aliases) do
    ranges =
      aliases
      # iterating back to start means we won't have prior edits
      # clobber subsequent edits
      |> Enum.sort_by(& &1.range.start.line, :desc)
      |> Enum.uniq_by(& &1.range)
      |> Enum.map(fn %Alias{} = alias ->
        orig_range = alias.range

        %Range{
          start: %Position{orig_range.start | character: 1},
          end: %Position{orig_range.end | line: orig_range.end.line + 1, character: 1}
        }
      end)

    first_alias_index = length(ranges) - 1

    ranges
    |> Enum.with_index()
    |> Enum.map(fn
      {range, ^first_alias_index} ->
        # add a new line where the first alias was to make space
        # for the rewritten aliases
        Edit.new("\n", range)

      {range, _} ->
        Edit.new("", range)
    end)
  end

  defp check_aliases(%Document{}, %Analysis{} = analysis, %Range{} = range) do
    narroest_scope =
      analysis
      |> Analysis.scopes_at(range.start)
      |> narrorwest_scope(range.start)

    with %Scope{} <- narroest_scope,
         false <- Enum.empty?(narroest_scope.aliases) do
      :ok
    else
      _ ->
        :error
    end
  end

  defp aliases_in_scope(%Scope{} = scope) do
    scope.aliases
    |> Enum.filter(fn %Alias{} = scope_alias ->
      scope_alias.explicit? and Range.contains?(scope.range, scope_alias.range.start)
    end)
    |> Enum.sort_by(& &1.module)
  end

  defp aliases_in_scope(_) do
    []
  end

  defp enclosing_scopes(scopes, range) do
    Enum.filter(scopes, fn scope ->
      Range.contains?(scope.range, range.start)
    end)
  end

  defp first_alias_range(aliases) do
    aliases
    |> Enum.min_by(fn %Alias{} = a ->
      {a.range.start.line, a.range.start.character}
    end)
    |> Map.get(:range)
  end

  defp join(module) do
    Enum.join(module, ".")
  end

  defp indent(text, spaces) do
    String.duplicate(" ", spaces) <> text
  end

  defp narrorwest_scope(scope_list, %Position{} = position) do
    Enum.reduce(scope_list, nil, fn
      scope, nil ->
        scope

      %Scope{id: :global}, %Scope{} = current ->
        current

      %Scope{} = next_scope, %Scope{} = current_scope ->
        Enum.min_by([next_scope, current_scope], fn %Scope{} = scope ->
          scope_start = scope.range.start
          position.line - scope_start.line
        end)
    end)
  end
end
