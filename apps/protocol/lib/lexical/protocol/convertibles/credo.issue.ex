defimpl Lexical.Convertible, for: Credo.Issue do
  alias Lexical.Document
  alias Lexical.Protocol.Diagnostic.Support
  alias Lexical.Protocol.Types
  alias Lexical.Protocol.Types.Diagnostic.Severity

  require Severity

  def to_lsp(%Credo.Issue{line_no: line_no} = issue, _context_document) do
    position = if issue.column, do: {line_no, issue.column}, else: line_no
    diagnostic_uri = Document.Path.ensure_uri(issue.filename)

    with {:ok, document} <- Document.Store.open_temporary(diagnostic_uri),
         {:ok, lsp_range} <- Support.position_to_range(document, position) do
      proto_diagnostic = %Types.Diagnostic{
        message: issue.message,
        range: lsp_range,
        severity: priority_to_security(issue),
        source: "Credo"
      }

      {:ok, proto_diagnostic}
    end
  end

  def to_native(%Credo.Issue{} = issue, _) do
    {:ok, issue}
  end

  # @dialyzer {:nowarn_function, to_atom: 1}

  defp priority_to_security(%Credo.Issue{priority: priority}) do
    case Credo.Priority.to_atom(priority) do
      :higher -> Severity.error()
      :high -> Severity.error()
      :normal -> Severity.warning()
      :low -> Severity.information()
      :ignore -> Severity.hint()
      _ -> Severity.hint()
    end
  end
end
