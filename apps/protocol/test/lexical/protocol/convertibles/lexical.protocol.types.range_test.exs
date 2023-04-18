defmodule Lexical.Protocol.Types.Convertibles.RangeTest do
  use Lexical.Test.Protocol.ConvertibleSupport

  describe "to_lsp/2" do
    setup [:with_an_open_file]

    test "converts native ranges", %{uri: uri} do
      native_range = range(:native, position(:native, 1, 1), position(:native, 1, 3))

      assert {:ok, %Types.Range{} = range} = to_lsp(native_range, uri)

      assert %Types.Position{} = range.start
      assert %Types.Position{} = range.end
    end

    test "leaves protocol ranges alone", %{uri: uri} do
      lsp_range = valid_range(:lsp)
      assert {:ok, ^lsp_range} = to_lsp(lsp_range, uri)
    end

    test "converts native positions inside lsp ranges", %{uri: uri} do
      lsp_range = range(:lsp, valid_position(:native), valid_position(:lsp))

      assert %SourceFile.Position{} = lsp_range.start

      assert {:ok, converted} = to_lsp(lsp_range, uri)
      assert %Types.Position{} = converted.start
    end
  end

  describe "to_native/2" do
    setup [:with_an_open_file]

    test "converts lsp ranges", %{uri: uri} do
      lsp_range = range(:lsp, position(:lsp, 0, 0), position(:lsp, 0, 3))
      assert {:ok, %SourceFile.Range{} = range} = to_native(lsp_range, uri)

      assert %SourceFile.Position{} = range.start
      assert %SourceFile.Position{} = range.end
    end

    test "leaves native ranges alone", %{uri: uri} do
      native_range = valid_range(:native)
      assert {:ok, ^native_range} = to_native(native_range, uri)
    end

    test "errors on invalid start position line", %{uri: uri} do
      invalid_range = range(:lsp, position(:lsp, -1, 0), valid_position(:lsp))
      assert {:error, {:invalid_range, ^invalid_range}} = to_native(invalid_range, uri)
    end

    test "errors on invalid end position line", %{uri: uri} do
      invalid_range = range(:lsp, valid_position(:lsp), position(:lsp, -1, 0))
      assert {:error, {:invalid_range, ^invalid_range}} = to_native(invalid_range, uri)
    end

    test "errors on invalid start position character", %{uri: uri} do
      invalid_range = range(:lsp, position(:lsp, 0, -1), valid_position(:lsp))
      assert {:error, {:invalid_range, ^invalid_range}} = to_native(invalid_range, uri)
    end

    test "errors on invalid end position character", %{uri: uri} do
      invalid_range = range(:lsp, valid_position(:lsp), position(:lsp, 0, -1))
      assert {:error, {:invalid_range, ^invalid_range}} = to_native(invalid_range, uri)
    end
  end
end
