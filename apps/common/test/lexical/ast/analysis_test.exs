defmodule Lexical.Ast.AnalysisTest do
  alias Lexical.Ast

  import Lexical.Test.CursorSupport
  import Lexical.Test.CodeSigil

  use ExUnit.Case

  defp analyze(text) do
    {_, document} = pop_cursor(text, as: :document)
    Ast.analyze(document)
  end

  describe "scope trees" do
    defp simplify_tree(%{scope: scope, children: children}) do
      {simplify_scope(scope), Enum.map(children, &simplify_tree/1)}
    end

    defp simplify_scope(scope) do
      {scope.kind, scope.module}
    end

    test "are constructed when a document is analyzed" do
      code = ~q[
        defmodule Outer do
          alias Foo.Bar

          defmodule Inner1 do
            alias Bar.Baz

            def qux do
              alias Qux.Inner
              :ok
            end
          end

          defmodule Inner2 do
            alias Bar.Baz
          end
        end
      ]

      assert {{:block, []},
              [
                {{:module, [:Outer]},
                 [
                   {{:block, [:Outer]},
                    [
                      {{:module, [:Outer, :Inner1]},
                       [
                         {{:block, [:Outer, :Inner1]},
                          [
                            {{:block, [:Outer, :Inner1]}, []}
                          ]}
                       ]},
                      {{:module, [:Outer, :Inner2]},
                       [
                         {{:block, [:Outer, :Inner2]}, []}
                       ]}
                    ]}
                 ]}
              ]} = code |> analyze() |> Map.fetch!(:tree) |> simplify_tree()
    end
  end
end
