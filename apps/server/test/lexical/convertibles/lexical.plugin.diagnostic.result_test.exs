defmodule Lexical.Convertibles.Lexical.Plugin.V1.Diagnostic.ResultTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic
  use Lexical.Test.Protocol.ConvertibleSupport

  import Lexical.Test.CodeSigil

  defp plugin_diagnostic(file_path, position) do
    file_path
    |> Document.Path.ensure_uri()
    |> Diagnostic.Result.new(position, "Broken!", :error, "Elixir")
  end

  def open_file_contents do
    ~q[
      defmodule UnderTest do
        def fun_one do
        end

        def fun_two do
          "🎸hello"
        end
      end
    ]t
  end

  describe "to_lsp/2" do
    setup [:with_an_open_file]

    test "it should translate a diagnostic with a line as a position", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{} = converted} = to_lsp(plugin_diagnostic(uri, 1), uri)

      assert converted.message == "Broken!"
      assert converted.severity == :error
      assert converted.source == "Elixir"
      assert converted.range == range(:lsp, position(:lsp, 0, 0), position(:lsp, 1, 0))
    end

    test "it should translate a diagnostic with a line and a column", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{} = converted} = to_lsp(plugin_diagnostic(uri, {1, 1}), uri)

      assert converted.message == "Broken!"
      assert converted.range == range(:lsp, position(:lsp, 0, 0), position(:lsp, 1, 0))
    end

    @tag :current
    test "it should translate a diagnostic with a four-elements tuple position", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{} = converted} =
               to_lsp(plugin_diagnostic(uri, {2, 5, 2, 8}), uri)

      assert converted.message == "Broken!"
      assert converted.range == range(:lsp, position(:lsp, 1, 4), position(:lsp, 1, 7))

      assert {:ok, %Types.Diagnostic{} = converted} =
               to_lsp(plugin_diagnostic(uri, {1, 0, 3, 0}), uri)

      assert converted.message == "Broken!"
      assert converted.range == range(:lsp, position(:lsp, 0, 0), position(:lsp, 2, 0))
    end

    test "it should translate a diagnostic line that is out of bounds (elixir can do this)", %{
      uri: uri
    } do
      assert {:ok, %Types.Diagnostic{} = converted} = to_lsp(plugin_diagnostic(uri, 9), uri)

      assert converted.message == "Broken!"
      assert converted.range == range(:lsp, position(:lsp, 7, 0), position(:lsp, 8, 0))
    end

    test "it can translate a diagnostic of a file that isn't open", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{}} = to_lsp(plugin_diagnostic(__ENV__.file, 2), uri)
    end

    test "it can translate a diagnostic that starts after an emoji", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{} = converted} = to_lsp(plugin_diagnostic(uri, {6, 10}), uri)

      assert converted.range == range(:lsp, position(:lsp, 5, 7), position(:lsp, 6, 0))
    end

    test "it converts lexical positions", %{uri: uri, document: document} do
      assert {:ok, %Types.Diagnostic{} = converted} =
               to_lsp(plugin_diagnostic(uri, Document.Position.new(document, 1, 1)), uri)

      assert converted.range == %Types.Range{
               start: %Types.Position{line: 0, character: 0},
               end: %Types.Position{line: 1, character: 0}
             }
    end

    test "it converts lexical ranges", %{uri: uri, document: document} do
      lexical_range =
        Document.Range.new(
          Document.Position.new(document, 2, 5),
          Document.Position.new(document, 2, 8)
        )

      assert {:ok, %Types.Diagnostic{} = converted} =
               to_lsp(plugin_diagnostic(uri, lexical_range), uri)

      assert %Types.Range{start: start_pos, end: end_pos} = converted.range
      assert start_pos.line == 1
      assert start_pos.character == 4
      assert end_pos.line == 1
      assert end_pos.character == 7
    end
  end
end
