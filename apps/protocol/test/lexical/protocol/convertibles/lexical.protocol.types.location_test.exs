defmodule Lexical.Protocol.Types.Convertibles.LocationTest do
  use Lexical.Test.Protocol.ConvertibleSupport

  describe "to_lsp/2" do
    setup [:with_an_open_file]

    test "converts a native location", %{uri: uri} do
      native_loc = SourceFile.Location.new(valid_range(:native), uri)

      assert {:ok, %Types.Location{} = converted} = to_lsp(native_loc, uri)

      assert converted.uri == uri
      assert %Types.Range{} = converted.range
      assert %Types.Position{} = converted.range.start
      assert %Types.Position{} = converted.range.end
    end

    test "uses the location's uri", %{uri: uri} do
      other_uri = "file:///other.ex"

      native_loc = SourceFile.Location.new(valid_range(:native), other_uri)
      assert {:ok, %Types.Location{} = converted} = to_lsp(native_loc, uri)

      assert converted.uri == other_uri
    end

    test "converts a lsp location with a native range", %{uri: uri} do
      lsp_loc = Types.Location.new(range: valid_range(:native), uri: uri)

      assert {:ok, %Types.Location{} = converted} = to_lsp(lsp_loc, uri)

      assert converted.uri == uri
      assert %Types.Range{} = converted.range
      assert %Types.Position{} = converted.range.start
      assert %Types.Position{} = converted.range.end
    end

    test "converts a lsp location with a native position", %{uri: uri} do
      lsp_loc =
        Types.Location.new(
          range: range(:lsp, valid_position(:native), valid_position(:lsp)),
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

      assert {:ok, %SourceFile.Location{} = converted} = to_native(lsp_loc, uri)

      assert converted.uri == uri
      assert %SourceFile.Range{} = converted.range
      assert %SourceFile.Position{} = converted.range.start
      assert %SourceFile.Position{} = converted.range.end
    end

    test "uses the location's uri", %{uri: uri} do
      other_uri = "file:///other.ex"
      lsp_loc = Types.Location.new(range: valid_range(:lsp), uri: other_uri)

      assert {:ok, %SourceFile.Location{} = converted} = to_native(lsp_loc, uri)

      assert converted.uri == uri
      assert %SourceFile.Range{} = converted.range
      assert %SourceFile.Position{} = converted.range.start
      assert %SourceFile.Position{} = converted.range.end
    end
  end
end
