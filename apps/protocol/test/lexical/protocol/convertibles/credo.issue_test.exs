defmodule Lexical.Convertibles.Mix.Task.Compiler.DiagnosticTest do
  use Lexical.Test.Protocol.ConvertibleSupport

  import Lexical.Test.CodeSigil

  defp credo_issue(file_path, line_no, column) do
    %Credo.Issue{
      check: Credo.Check.Refactor.FilterFilter,
      category: :refactor,
      priority: 1,
      severity: 1,
      message: "One `Enum.filter/2` is more efficient than `Enum.filter/2 |> Enum.filter/2`",
      filename: file_path,
      line_no: line_no,
      column: column,
      exit_status: 8,
      trigger: "|>",
      diff_marker: nil,
      meta: [],
      scope: "Dummy.hello"
    }
  end

  def open_file_contents do
    ~q{
    defmodule Dummy do
      @moduledoc false

      def hello do
        :world

        ["a", "b", "c"]
        |> Enum.filter(&String.contains?(&1, "x"))
        |> Enum.filter(&String.contains?(&1, "a"))
      end
    end
  }t
  end

  describe "to_lsp/2" do
    setup [:with_an_open_file]

    test "it should translate a diagnostic with a line as a position", %{uri: uri} do
      assert {:ok, %Types.Diagnostic{} = converted} = to_lsp(credo_issue(uri, 8, nil), uri)

      assert converted.message ==
               "One `Enum.filter/2` is more efficient than `Enum.filter/2 |> Enum.filter/2`"

      assert converted.severity == 2
      assert converted.source == "Credo"
      assert converted.range == range(:lsp, position(:lsp, 7, 4), position(:lsp, 8, 0))
    end
  end
end
