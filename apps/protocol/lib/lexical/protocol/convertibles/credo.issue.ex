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

  defp priority_to_security(%Credo.Issue{priority: priority}) do
    case to_atom(priority) do
      :higher -> :error
      :high -> :error
      :normal -> :warning
      :low -> :information
      :ignore -> :hint
      _ -> :hint
    end
  end

  @doc """
  Copied from Credo.Priority
  """
  def to_atom(priority)

  def to_atom(priority) when is_number(priority) do
    cond do
      priority > 19 -> :higher
      priority in 10..19 -> :high
      priority in 0..9 -> :normal
      priority in -10..-1 -> :low
      priority < -10 -> :ignore
    end
  end

  def to_atom(%{priority: priority}), do: to_atom(priority)

  def to_atom(priority) when is_atom(priority), do: priority

  def to_atom(_), do: nil
end
