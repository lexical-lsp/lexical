defimpl Lexical.Convertible, for: Mix.Task.Compiler.Diagnostic do
  alias Lexical.Document
  alias Lexical.Protocol.Diagnostic.Support
  alias Lexical.Protocol.Types
  alias Mix.Task.Compiler

  def to_lsp(%Compiler.Diagnostic{} = diagnostic, _context_document) do
    diagnostic_uri = Document.Path.ensure_uri(diagnostic.file)

    with {:ok, document} <- Document.Store.open_temporary(diagnostic_uri),
         {:ok, lsp_range} <- Support.position_to_range(document, diagnostic.position) do
      proto_diagnostic = %Types.Diagnostic{
        message: diagnostic.message,
        range: lsp_range,
        severity: diagnostic.severity,
        source: "Elixir"
      }

      {:ok, proto_diagnostic}
    end
  end

  def to_native(%Compiler.Diagnostic{} = diagnostic, _) do
    {:ok, diagnostic}
  end
end
