defmodule Lexical.RemoteControl.AnalyzerTest do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.RemoteControl.Analyzer

  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport

  use ExUnit.Case, async: true

  describe "expand_alias/4" do
    test "works with __MODULE__ aliases" do
      {position, document} =
        ~q[
          defmodule Parent do
            defmodule __MODULE__.Child do
              |
            end
          end
        ]
        |> pop_cursor(as: :document)

      analysis = Ast.analyze(document)

      assert {:ok, Parent.Child} =
               Analyzer.expand_alias([quote(do: __MODULE__), nil], analysis, position)
    end

    test "works with @protocol in a protocol" do
      {position, document} =
        ~q[
        defimpl MyProtocol, for: Atom do

          def pack(atom) do
            |
          end
        end
        ]
        |> pop_cursor(as: :document)

      analysis = Ast.analyze(document)

      assert {:ok, MyProtocol} = Analyzer.expand_alias([quote(do: @protocol)], analysis, position)

      assert {:ok, MyProtocol.BitString} =
               Analyzer.expand_alias([quote(do: @protocol.BitString)], analysis, position)

      assert {:ok, Atom} = Analyzer.expand_alias([quote(do: @for)], analysis, position)

      assert {:ok, Atom.Something} =
               Analyzer.expand_alias([quote(do: @for.Something)], analysis, position)

      assert {:ok, MyProtocol.BitString} =
               Analyzer.expand_alias(
                 [
                   {:@, [line: 9, column: 8], [{:protocol, [line: 9, column: 9], nil}]},
                   :BitString
                 ],
                 analysis,
                 position
               )
    end

    test "identifies the module in a protocol implementation" do
      {position, document} =
        ~q[
          defimpl MyProtocol, for: Atom do

            def pack(atom) do
              |
            end
          end
        ]
        |> pop_cursor(as: :document)

      analysis = Ast.analyze(document)
      assert {:ok, MyProtocol.Atom} == Analyzer.current_module(analysis, position)
    end
  end

  describe "reanalyze_to/2" do
    test "is a no-op if the analysis is already valid" do
      {position, document} =
        ~q[
          defmodule Valid do
            |
          end
        ]
        |> pop_cursor(as: :document)

      assert %Analysis{valid?: true} = analysis = Ast.analyze(document)
      assert analysis == Ast.reanalyze_to(analysis, position)
    end

    test "returns a valid analysis if fragment can be parsed" do
      {position, document} =
        ~q[
          defmodule Invalid do
            |
        ]
        |> pop_cursor(as: :document)

      assert %Analysis{valid?: false} = analysis = Ast.analyze(document)
      assert %Analysis{valid?: true} = analysis = Ast.reanalyze_to(analysis, position)
      assert {:ok, Invalid} = Analyzer.current_module(analysis, position)
    end
  end
end
