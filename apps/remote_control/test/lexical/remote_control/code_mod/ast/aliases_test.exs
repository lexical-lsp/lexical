defmodule Lexical.RemoteControl.CodeMod.Ast.AliasesTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.CodeMod.Ast.Aliases
  alias Lexical.Test.CodeSigil
  alias Lexical.Test.CursorSupport

  import Aliases
  import CursorSupport
  import CodeSigil

  use ExUnit.Case

  def aliases_at_cursor(text) do
    pos = cursor_position(text)
    text = strip_cursor(text)
    doc = Document.new("file:///file.ex", text, 0)
    at(doc, pos)
  end

  describe "top level aliases" do
    test "a useless alias" do
      aliases =
        ~q[
          alias Foo
          |
        ]
        |> aliases_at_cursor()

      assert aliases[:Foo] == Foo
    end

    test "an alias outside of a module" do
      aliases =
        ~q[
        alias Foo.Bar.Baz
        defmodule Parent do
          |
        end
      ]
        |> aliases_at_cursor()

      assert aliases[:Baz] == Foo.Bar.Baz
    end

    test "an alias inside the body of a module" do
      aliases =
        ~q[
          defmodule Basic do
            alias Foo.Bar
            |
          end
          ]
        |> aliases_at_cursor()

      assert aliases == %{__MODULE__: Basic, Bar: Foo.Bar, Basic: Basic}
    end

    test "an alias using as" do
      aliases =
        ~q[
          defmodule TopLevel do
            alias Foo.Bar, as: FooBar
            |
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:__MODULE__] == TopLevel
      assert aliases[:FooBar] == Foo.Bar
    end

    test "multiple aliases off of single alias" do
      aliases =
        ~q[
          defmodule TopLevel do
            alias Foo.{First, Second, Third.Fourth}
            |
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:First] == Foo.First
      assert aliases[:Second] == Foo.Second
      assert aliases[:Fourth] == Foo.Third.Fourth
    end

    test "multiple aliases off of nested alias" do
      aliases =
        ~q[
          defmodule TopLevel do
            alias Foo.Bar.{First, Second, Third.Fourth}
            |
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:First] == Foo.Bar.First
      assert aliases[:Second] == Foo.Bar.Second
      assert aliases[:Fourth] == Foo.Bar.Third.Fourth
    end

    test "aliasing __MODULE__" do
      aliases =
        ~q[
          defmodule Something.Is.Nested do
            alias __MODULE__|

          end
        ]
        |> aliases_at_cursor()

      assert aliases[:Nested] == Something.Is.Nested
    end

    test "multiple aliases leading by current module" do
      aliases =
        ~q[
          defmodule TopLevel do
            alias __MODULE__.{First, Second}
            |
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:First] == TopLevel.First
      assert aliases[:Second] == TopLevel.Second
    end

    test "multiple aliases leading by current module's child" do
      aliases =
        ~q[
          defmodule TopLevel do
            alias __MODULE__.Child.{First, Second}
            |
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:First] == TopLevel.Child.First
      assert aliases[:Second] == TopLevel.Child.Second
    end

    test "aliases expanding other aliases" do
      aliases =
        ~q[
          alias Foo.Bar.Baz
          alias Baz.Quux|
        ]
        |> aliases_at_cursor()

      assert aliases[:Baz] == Foo.Bar.Baz
      assert aliases[:Quux] == Foo.Bar.Baz.Quux
    end

    test "aliases expanding current module" do
      aliases = ~q[
        defmodule TopLevel do
          alias __MODULE__.Foo|
        end
      ] |> aliases_at_cursor()

      assert aliases[:Foo] == TopLevel.Foo
    end

    test "aliases expanding current module using as" do
      aliases = ~q[
        defmodule TopLevel do
          alias __MODULE__.Foo|, as: OtherAlias
        end
      ] |> aliases_at_cursor()

      assert aliases[:OtherAlias] == TopLevel.Foo
    end

    test "allows overrides" do
      aliases =
        ~q[
          alias Foo.Bar.Baz
          alias Other.Baz
        ]
        |> aliases_at_cursor()

      assert aliases[:Baz] == Other.Baz
    end
  end

  describe "nested modules" do
    test "no aliases are defined for modules with dots" do
      aliases =
        ~q[
          defmodule GrandParent.Parent.Child do
           |
          end
        ]
        |> aliases_at_cursor()

      refute Map.has_key?(aliases, :Child)
    end

    test "with children get their parents name" do
      aliases =
        ~q[
          defmodule Grandparent.Parent do
            defmodule Child do
              |
            end
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:Child] == Grandparent.Parent.Child
      assert aliases[:__MODULE__] == Grandparent.Parent.Child
    end
  end

  describe "alias scopes" do
    test "aliases are removed when leaving a module" do
      aliases =
        ~q[
          defmodule Basic do
            alias Foo.Bar
          end|
        ]
        |> aliases_at_cursor()

      assert aliases == %{Basic: Basic, __MODULE__: nil}
    end

    test "aliases inside of nested modules" do
      aliases =
        ~q[
          defmodule Parent do
            alias Foo.Grandparent

            defmodule Child do
              alias Foo.Something
              |
            end
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:Grandparent] == Foo.Grandparent
      assert aliases[:Something] == Foo.Something
      assert aliases[:__MODULE__] == Parent.Child
      assert aliases[:Child] == Parent.Child
    end

    test "multiple nested module are aliased after definition" do
      aliases =
        ~q[
          defmodule Parent do
            alias Foo.Grandparent

            defmodule Child do
              alias Foo.Something
            end

            defmodule AnotherChild do
              alias Foo.Something
            end
            |
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:AnotherChild] == Parent.AnotherChild
      assert aliases[:Child] == Parent.Child
    end

    test "an alias defined in a named function" do
      aliases =
        ~q[
          defmodule Parent do
            def fun do
              alias Foo.Parent
            |
            end
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:Parent] == Foo.Parent
    end

    test "an alias defined in a named function doesn't leak" do
      aliases =
        ~q[
          defmodule Parent do
            def fun do
              alias Foo.Parent
            end|
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:Parent] == Parent
    end

    test "an alias defined in a private named function" do
      aliases =
        ~q[
          defmodule Parent do
            defp fun do
              alias Foo.Parent
              |
            end
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:Parent] == Foo.Parent
    end

    test "an alias defined in a private named function doesn't leak" do
      aliases =
        ~q[
          defmodule Parent do
            defp fun do
              alias Foo.InFun
            end|
          end
        ]
        |> aliases_at_cursor()

      refute aliases[:InFun]
    end

    test "an alias defined in a DSL" do
      aliases =
        ~q[
          defmodule Parent do
             my_dsl do
              alias Foo.Parent
              |
            end
          end
        ]
        |> aliases_at_cursor()

      assert aliases[:Parent] == Foo.Parent
    end

    test "an alias defined in a DSL does not leak" do
      aliases =
        ~q[
          defmodule Parent do
             my_dsl do
              alias Foo.InDSL
             end
             |
          end
        ]
        |> aliases_at_cursor()

      refute aliases[InDsl]
    end

    # Note: it looks like Code.container_cursor_to_quoted doesn't work with
    # anonymous functions
    @tag :skip
    test "an alias defined in a anonymous function"

    @tag :skip
    test "an alias defined in a anonymous function doesn't leak"
  end
end
