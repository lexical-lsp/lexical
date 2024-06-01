defmodule Lexical.RemoteControl.CodeAction.Handlers.OrganizeAliases do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeAction
  alias Lexical.RemoteControl.CodeMod

  require Logger

  @behaviour CodeAction.Handler

  @impl CodeAction.Handler
  def actions(%Document{} = doc, %Range{} = range, _diagnostics) do
    with {:ok, _doc, analysis} <- Document.Store.fetch(doc.uri, :analysis),
         :ok <- check_aliases(doc, analysis, range) do
      aliases = CodeMod.Aliases.in_scope(analysis, range)
      {insert_position, trailer} = CodeMod.Aliases.insert_position(analysis, range.start)
      edits = CodeMod.Aliases.to_edits(aliases, insert_position, trailer)

      if Enum.empty?(edits) do
        []
      else
        changes = Changes.new(doc, edits)
        [CodeAction.new(doc.uri, "Organize aliases", :source_organize_imports, changes)]
      end
    else
      _ ->
        []
    end
  end

  @impl CodeAction.Handler
  def kinds do
    [:source, :source_organize_imports]
  end

  defp check_aliases(%Document{}, %Analysis{} = analysis, %Range{} = range) do
    with %Scope{aliases: [_ | _]} <- Analysis.module_scope(analysis, range),
         true <-
           ancestor_is_alias?(analysis, range.start) or
             token_at_cursor_is_alias?(analysis, range.start) do
      :ok
    else
      _ ->
        :error
    end
  end

  defp ancestor_is_alias?(%Analysis{} = analysis, %Position{} = position) do
    analysis
    |> Ast.cursor_path(position)
    |> Enum.any?(fn
      {:alias, _, _} ->
        true

      _ ->
        false
    end)
  end

  defp token_at_cursor_is_alias?(%Analysis{} = analysis, %Position{} = position) do
    project = RemoteControl.get_project()
    {:ok, env} = Ast.Env.new(project, analysis, position)
    (env.prefix <> env.suffix) |> String.trim_leading() |> String.starts_with?("alias")
  end
end
