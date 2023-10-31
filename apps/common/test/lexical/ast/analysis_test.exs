defmodule Lexical.Ast.AnalysisTest do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document

  import Lexical.Test.CodeSigil
  import Lexical.Test.PositionSupport

  use ExUnit.Case, async: true

  defp analyze(code) when is_binary(code) do
    document = Document.new("file:///file.ex", code, 0)
    Ast.analyze(document)
  end

  describe "aliases_at/2" do
    test "extracts nested module scopes and aliases" do
      code = ~q[
        defmodule Outer do
          alias Namespace.Foo

          defmodule Inner1 do
            alias Namespace.Bar
          end

          defmodule Inner2 do
            alias Namespace.Baz
          end
        end
      ]

      assert %Analysis{} = analysis = analyze(code)

      assert %{Outer: _, __MODULE__: _} = Analysis.aliases_at(analysis, position(2, 1))

      assert %{Foo: _, Outer: _, __MODULE__: _} = Analysis.aliases_at(analysis, position(3, 1))

      assert %{Bar: _, Inner1: _, Foo: _, Outer: _, __MODULE__: _} =
               Analysis.aliases_at(analysis, position(6, 1))

      assert %{Inner1: _, Foo: _, Outer: _, __MODULE__: _} =
               Analysis.aliases_at(analysis, position(7, 1))

      assert %{Baz: _, Inner2: _, Inner1: _, Foo: _, Outer: _, __MODULE__: _} =
               Analysis.aliases_at(analysis, position(10, 1))

      assert %{Inner2: _, Inner1: _, Foo: _, Outer: _, __MODULE__: _} =
               Analysis.aliases_at(analysis, position(10, 6))
    end
  end
end
