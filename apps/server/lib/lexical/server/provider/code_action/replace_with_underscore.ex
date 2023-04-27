defmodule Lexical.Server.Provider.CodeAction.ReplaceWithUnderscore do
  @moduledoc """
  A code action that prefixes unused variables with an underscore
  """
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Project
  alias Lexical.Protocol.Requests.CodeAction
  alias Lexical.Protocol.Types.CodeAction, as: CodeActionResult
  alias Lexical.Protocol.Types.Diagnostic
  alias Lexical.Protocol.Types.Workspace
  alias Lexical.RemoteControl
  alias Lexical.Server.Provider.Env

  @spec apply(CodeAction.t(), Env.t()) :: [CodeActionResult.t()]
  def apply(%CodeAction{} = code_action, %Env{} = env) do
    document = code_action.document
    diagnostics = get_in(code_action, [:context, :diagnostics]) || []

    Enum.flat_map(diagnostics, fn %Diagnostic{} = diagnostic ->
      with {:ok, variable_name, line_number} <- extract_variable_and_line(diagnostic),
           {:ok, reply} <- build_code_action(env.project, document, line_number, variable_name) do
        [reply]
      else
        _ ->
          []
      end
    end)
  end

  defp build_code_action(
         %Project{} = project,
         %Document{} = document,
         line_number,
         variable_name
       ) do
    case RemoteControl.Api.replace_with_underscore(
           project,
           document,
           line_number,
           variable_name
         ) do
      {:ok, []} ->
        :error

      {:ok, %Changes{} = document_edits} ->
        reply =
          CodeActionResult.new(
            title: "Rename to _#{variable_name}",
            kind: :quick_fix,
            edit: Workspace.Edit.new(changes: %{document.uri => document_edits})
          )

        {:ok, reply}
    end
  end

  defp extract_variable_and_line(%Diagnostic{} = diagnostic) do
    with {:ok, variable_name} <- extract_variable_name(diagnostic.message),
         {:ok, line} <- extract_line(diagnostic) do
      {:ok, variable_name, line}
    end
  end

  @variable_re ~r/variable "([^"]+)" is unused/
  defp extract_variable_name(message) do
    case Regex.scan(@variable_re, message) do
      [[_, variable_name]] ->
        {:ok, String.to_atom(variable_name)}

      _ ->
        :error
    end
  end

  defp extract_line(%Diagnostic{} = diagnostic) do
    {:ok, diagnostic.range.start.line}
  end
end
