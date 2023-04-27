defmodule Lexical.Convertibles.Mix.Task.Compiler.DiagnosticTest do
  alias Mix.Task.Compiler
  use Lexical.Test.Protocol.ConvertibleSupport

  import Lexical.Test.CodeSigil

  defp compiler_diagnostic(file_path, position) do
    %Compiler.Diagnostic{
      file: Document.Path.ensure_path(file_path),
      position: position,
      severity: :error,
      message: "Broken!",
      compiler_name: "Elixir"
    }
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
      assert {:ok, %Types.Diagnostic{} = converted} = to_lsp(compiler_diagnostic(uri, 1), uri)

      assert converted.message == "Broken!"
      assert converted.severity == :error
      assert converted.source == "Elixir"
      assert converted.range == range(:lsp, position(:lsp, 0, 0), position(:lsp, 1, 0))
    end

    test "it should translate a diagnostic with a line and a column", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{} = converted} =
               to_lsp(compiler_diagnostic(uri, {1, 1}), uri)

      assert converted.message == "Broken!"
      assert converted.range == range(:lsp, position(:lsp, 0, 0), position(:lsp, 1, 0))
    end

    test "it should translate a diagnostic line that is out of bounds (elixir can do this)", %{
      uri: uri
    } do
      assert {:ok, %Types.Diagnostic{} = converted} = to_lsp(compiler_diagnostic(uri, 9), uri)

      assert converted.message == "Broken!"
      assert converted.range == range(:lsp, position(:lsp, 7, 0), position(:lsp, 8, 0))
    end

    test "it can translate a diagnostic of a file that isn't open", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{}} = to_lsp(compiler_diagnostic(__ENV__.file, 2), uri)
    end

    test "it can translate a diagnostic that starts after an emoji", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{} = converted} =
               to_lsp(compiler_diagnostic(uri, {6, 10}), uri)

      assert converted.range == range(:lsp, position(:lsp, 5, 7), position(:lsp, 6, 0))
    end
  end
end
