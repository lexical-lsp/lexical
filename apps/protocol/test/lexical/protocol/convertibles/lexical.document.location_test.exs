defmodule Lexical.Protocol.Convertibles.LocationTest do
  use Lexical.Test.Protocol.ConvertibleSupport

  describe "to_lsp/2" do
    setup [:with_an_open_file]

    test "converts a location with a native range", %{uri: uri, document: document} do
      location = Document.Location.new(valid_range(:native, document), uri)

      assert {:ok, converted} = to_lsp(location, uri)
      assert converted.uri == uri
      assert %Types.Range{} = converted.range
      assert %Types.Position{} = converted.range.start
      assert %Types.Position{} = converted.range.end
    end

    test "converts a location with a source file", %{uri: uri, document: document} do
      location = Document.Location.new(valid_range(:native, document), document)

      assert {:ok, converted} = to_lsp(location, uri)
      assert converted.uri == document.uri
      assert %Types.Range{} = converted.range
      assert %Types.Position{} = converted.range.start
      assert %Types.Position{} = converted.range.end
    end

    test "uses the location's uri", %{uri: uri, document: document} do
      other_uri = "file:///other.ex"
      {:ok, _, _doc} = open_file(other_uri, "goodbye")

      location = Document.Location.new(valid_range(:native, document), other_uri)
      assert {:ok, converted} = to_lsp(location, uri)
      assert converted.uri == other_uri
    end
  end

  describe "to_native/2" do
    setup [:with_an_open_file]

    test "leaves the location alone", %{uri: uri, document: document} do
      location = Document.Location.new(valid_range(:native, document), uri)

      assert {:ok, converted} = to_native(location, uri)
      assert location == converted
    end
  end
end
