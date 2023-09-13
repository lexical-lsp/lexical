defmodule Lexical.Protocol.Types.Convertibles.LocationTest do
  use Lexical.Test.Protocol.ConvertibleSupport

  describe "to_lsp/2" do
    setup [:with_an_open_file]

    test "converts a native location", %{uri: uri, document: document} do
      native_loc = Document.Location.new(valid_range(:native, document), uri)

      assert {:ok, %Types.Location{} = converted} = to_lsp(native_loc, uri)

      assert converted.uri == uri
      assert %Types.Range{} = converted.range
      assert %Types.Position{} = converted.range.start
      assert %Types.Position{} = converted.range.end
    end

    test "uses the location's uri", %{uri: uri, document: document} do
      other_uri = "file:///other.ex"

      native_loc = Document.Location.new(valid_range(:native, document), other_uri)
      assert {:ok, %Types.Location{} = converted} = to_lsp(native_loc, uri)

      assert converted.uri == other_uri
    end

    test "converts a lsp location with a native range", %{uri: uri, document: document} do
      lsp_loc = Types.Location.new(range: valid_range(:native, document), uri: uri)

      assert {:ok, %Types.Location{} = converted} = to_lsp(lsp_loc, uri)

      assert converted.uri == uri
      assert %Types.Range{} = converted.range
      assert %Types.Position{} = converted.range.start
      assert %Types.Position{} = converted.range.end
    end

    test "converts a lsp location with a native position", %{uri: uri, document: document} do
      lsp_loc =
        Types.Location.new(
          range: range(:lsp, valid_position(:native, document), valid_position(:lsp)),
          uri: uri
        )

      assert {:ok, %Types.Location{} = converted} = to_lsp(lsp_loc, uri)

      assert converted.uri == uri
      assert %Types.Range{} = converted.range
      assert %Types.Position{} = converted.range.start
      assert %Types.Position{} = converted.range.end
    end
  end

  describe "to_native/2" do
    setup [:with_an_open_file]

    test "converts an lsp location", %{uri: uri} do
      lsp_loc = Types.Location.new(range: valid_range(:lsp), uri: uri)

      assert {:ok, %Document.Location{} = converted} = to_native(lsp_loc, uri)

      assert converted.uri == uri
      assert %Document.Range{} = converted.range
      assert %Document.Position{} = converted.range.start
      assert %Document.Position{} = converted.range.end
    end

    test "uses the location's uri", %{uri: uri} do
      other_uri = "file:///other.ex"
      lsp_loc = Types.Location.new(range: valid_range(:lsp), uri: other_uri)

      assert {:ok, %Document.Location{} = converted} = to_native(lsp_loc, uri)

      assert converted.uri == uri
      assert %Document.Range{} = converted.range
      assert %Document.Position{} = converted.range.start
      assert %Document.Position{} = converted.range.end
    end
  end
end
