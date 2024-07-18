defmodule Lexical.RemoteControl.CodeAction.Handlers.OrganizeAliasesTest do
  alias Lexical.Document
  alias Lexical.Document.Range
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeAction.Handlers.OrganizeAliases

  import Lexical.Test.CursorSupport
  import Lexical.Test.CodeSigil

  use Lexical.Test.CodeMod.Case, enable_ast_conversion: false
  use Patch

  setup do
    start_supervised!({Document.Store, derive: [analysis: &Lexical.Ast.analyze/1]})
    :ok
  end

  def apply_code_mod(text, _ast, options) do
    range = options[:range]
    uri = "file:///file.ex"
    :ok = Document.Store.open(uri, text, 1)
    {:ok, document} = Document.Store.fetch(uri)

    edits =
      case OrganizeAliases.actions(document, range, []) do
        [action] -> action.changes.edits
        _ -> []
      end

    {:ok, edits}
  end

  def organize_aliases(original_text) do
    {position, stripped_text} = pop_cursor(original_text)
    range = Range.new(position, position)
    modify(stripped_text, range: range)
  end

  describe "outside of a module" do
    test "aliases are sorted alphabetically" do
      {:ok, organized} =
        ~q[
          alias ZZ.XX.YY
          alias AA.BB.CC|
        ]
        |> organize_aliases()

      expected = ~q[
        alias AA.BB.CC
        alias ZZ.XX.YY
      ]t

      assert expected == organized
    end

    test "aliases are sorted in a case insensitive way" do
      {:ok, organized} =
        ~q[
        defmodule Outer do
          alias CSV
          alias Common|
        end
        ]
        |> organize_aliases()

      expected = ~q[
      defmodule Outer do
        alias Common
        alias CSV
      end
      ]t

      assert expected == organized
    end

    test "nested aliases are flattened" do
      {:ok, organized} =
        ~q[
        alias A.B.{C, D, E}|
        ]
        |> organize_aliases()

      expected = ~q[
        alias A.B.C
        alias A.B.D
        alias A.B.E
      ]t

      assert expected == organized
    end
  end

  describe "at the top of a module" do
    test "does nothing if there are no aliases" do
      patch(RemoteControl, :get_project, %Lexical.Project{})

      {:ok, organized} =
        ~q[
          defmodule Nothing do
            @attr true|
          end
        ]
        |> organize_aliases()

      expected = ~q[
      defmodule Nothing do
        @attr true
      end
      ]t

      assert expected == organized
    end

    test "aliases are sorted alphabetically " do
      {:ok, organized} =
        ~q[
          defmodule Simple do
            alias Z.X.Y|
            alias V.W.X, as: Unk
            alias A.B.C
          end
        ]
        |> organize_aliases()

      expected = ~q[
      defmodule Simple do
        alias A.B.C
        alias V.W.X, as: Unk
        alias Z.X.Y
      end
    ]t
      assert expected == organized
    end

    test "aliases are removed duplicate aliases" do
      {:ok, organized} =
        ~q[
          defmodule Dupes do
            alias Foo.Bar.Baz|
            alias Other.Thing
            alias Foo.Bar.Baz
          end
        ]
        |> organize_aliases()

      expected = ~q[
        defmodule Dupes do
          alias Foo.Bar.Baz
          alias Other.Thing
        end
      ]t
      assert expected == organized
    end

    test "dependent aliase are honored" do
      {:ok, organized} =
        ~q[
          defmodule Deps do
            alias First.Dep|
            alias Dep.Action
            alias Action.Third
            alias Third.Fourth.{Fifth, Sixth}
          end
        ]
        |> organize_aliases()

      expected = ~q[
      defmodule Deps do
        alias First.Dep
        alias First.Dep.Action
        alias First.Dep.Action.Third
        alias First.Dep.Action.Third.Fourth.Fifth
        alias First.Dep.Action.Third.Fourth.Sixth
      end
    ]t

      assert expected == organized
    end

    test "nested aliases are flattened" do
      {:ok, organized} =
        ~q[
          defmodule Nested do
            alias Foo.Bar.|{
              Baz,
              Quux,
              Quux.Foorp
            }
          end
        ]
        |> organize_aliases()

      expected = ~q[
      defmodule Nested do
        alias Foo.Bar.Baz
        alias Foo.Bar.Quux
        alias Foo.Bar.Quux.Foorp
      end
    ]t
      assert expected == organized
    end

    test "module attributes are kept " do
      {:ok, organized} =
        ~q[
          defmodule Simple do
            alias First.Second|
            @attr true
            alias Second.Third
          end
        ]
        |> organize_aliases()

      expected = ~q[
      defmodule Simple do
        alias First.Second
        alias First.Second.Third
        @attr true
      end
    ]t

      assert expected == organized
    end

    test "aliases in a given scope are pulled to the top" do
      patch(RemoteControl, :get_project, %Lexical.Project{})

      {:ok, organized} =
        ~q[
          defmodule Scattered do
            alias| My.Alias
            def my_function do
            end
            alias Another.Alias
            def other_function do
            end
            alias Yet.Another
          end
        ]
        |> organize_aliases()

      expected = ~q[
      defmodule Scattered do
        alias Another.Alias
        alias My.Alias
        alias Yet.Another
        def my_function do
        end
        def other_function do
        end
      end
      ]t

      assert expected == organized
    end

    test "aliases in different scopes are left alone" do
      {:ok, organized} =
        ~q[
        defmodule Outer do
          alias Foo.Bar|
          alias A.B

          def my_fn do
            alias Something.Else
            1 - Else.other(1)
          end
        end
        ]
        |> organize_aliases()

      expected = ~q[
      defmodule Outer do
        alias A.B
        alias Foo.Bar

        def my_fn do
          alias Something.Else
          1 - Else.other(1)
        end
      end
      ]t

      assert expected == organized
    end

    test "aliases in a nested module are left alone" do
      {:ok, organized} =
        ~q[
        defmodule Outer do
          alias Foo.Bar
          alias A.B

          defmodule Nested do
            alias Something.Else
            alias AA.BB |

            def nested_fn do
            end
            alias BB.CC
          end
        end
        ]
        |> organize_aliases()

      expected = ~q[
        defmodule Outer do
          alias Foo.Bar
          alias A.B

          defmodule Nested do
            alias AA.BB
            alias AA.BB.CC
            alias Something.Else

            def nested_fn do
            end
          end
        end
        ]t

      assert expected == organized
    end
  end

  describe "check the return conditions for the alias" do
    test "returns organized aliases if the cursor's immediate parent is a module" do
      patch(RemoteControl, :get_project, %Lexical.Project{})

      {:ok, organized} =
        ~q[
          defmodule Outer do
            alias Foo.Bar
            alias A.B.C
            alias D.E.F
            | a
          end] |> organize_aliases()

      expected =
        ~q[
          defmodule Outer do
            alias A.B.C
            alias D.E.F
            alias Foo.Bar
             a
          end]

      assert expected == organized
    end

    test "returns organized aliases if the cursor is at an alias" do
      patch(RemoteControl, :get_project, %Lexical.Project{})

      {:ok, organized} =
        ~q[
          defmodule Outer do
            |alias Foo.Bar
            alias A.B.C
            alias D.E.F
          end] |> organize_aliases()

      expected =
        ~q[
          defmodule Outer do
            alias A.B.C
            alias D.E.F
            alias Foo.Bar
          end]

      assert expected == organized
    end

    test "returns organized aliases if the cursor's ancesor is an alias" do
      {:ok, organized} =
        ~q[
          defmodule Outer do
            alias Foo.|Bar
            alias A.B.C
            alias D.E.F
          end] |> organize_aliases()

      expected =
        ~q[
          defmodule Outer do
            alias A.B.C
            alias D.E.F
            alias Foo.Bar
          end]

      assert expected == organized
    end

    test "does nothing if the cursor is at an `def` keyword" do
      patch(RemoteControl, :get_project, %Lexical.Project{})

      text =
        ~q[
          defmodule Outer do
            alias Foo.Bar
            alias A.B.C
            alias D.E.F

            |def my_fn do
              1 + 2
            end
          end]

      {:ok, organized} = organize_aliases(text)

      {_, original} = pop_cursor(text)
      assert original == organized
    end

    test "does nothing if the cursor is at the function name" do
      patch(RemoteControl, :get_project, %Lexical.Project{})

      text =
        ~q[
          defmodule Outer do
            alias Foo.Bar
            alias A.B.C
            alias D.E.F

            def |my_fn do
              1 + 2
            end
          end]

      {:ok, organized} = organize_aliases(text)

      {_, original} = pop_cursor(text)
      assert original == organized
    end
  end
end
