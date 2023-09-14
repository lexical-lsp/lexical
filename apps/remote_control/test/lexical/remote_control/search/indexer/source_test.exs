defmodule Lexical.RemoteControl.Search.Indexer.SourceTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer
  alias Lexical.Test.RangeSupport

  import Lexical.Test.CodeSigil
  import RangeSupport

  use ExUnit.Case

  def index(source) do
    path = "/foo/bar/baz.ex"
    doc = Document.new("file:///#{path}", source, 1)

    case Indexer.Source.index("/foo/bar/baz.ex", source) do
      {:ok, indexed_items} -> {:ok, indexed_items, doc}
      error -> error
    end
  end

  describe "indexing modules" do
    test "it doesn't confuse a list of atoms for a module" do
      {:ok, [module], _} =
        ~q(
          defmodule Root do
            @attr [:Some, :Other, :Module]
          end
        )
        |> index()

      assert module.type == :module
      assert module.subject == Root
    end

    test "indexes a flat module with no aliases" do
      {:ok, [entry], doc} =
        ~q[
        defmodule Simple do
        end
        ]
        |> index()

      assert entry.type == :module
      assert entry.parent == :root
      assert entry.subject == Simple
      assert decorate(doc, entry.range) =~ "defmodule «Simple» do"
    end

    test "indexes a flat module with a dotted name" do
      {:ok, [entry], doc} =
        ~q[
        defmodule Simple.Module.Path do
        end
        ]
        |> index()

      assert entry.subject == Simple.Module.Path
      assert entry.type == :module
      assert entry.parent == :root
      assert decorate(doc, entry.range) =~ "defmodule «Simple.Module.Path» do"
    end

    test "indexes a flat module with an aliased name" do
      {:ok, [_alias, entry], doc} =
        ~q[
        alias Something.Else
        defmodule Else.Other do
        end
      ]
        |> index()

      assert entry.subject == Something.Else.Other
      assert decorate(doc, entry.range) == "defmodule «Else.Other» do"
    end

    test "can detect an erlang module" do
      {:ok, [module_def, erlang_module], doc} =
        ~q[
        defmodule Root do
          @something :timer
        end
      ]
        |> index()

      assert erlang_module.type == :module
      assert erlang_module.parent == module_def.ref
      assert erlang_module.subject == :timer
      assert decorate(doc, erlang_module.range) =~ "  @something «:timer»"
    end

    test "can detect a module reference in a module attribute" do
      {:ok, [module_def, attribute], doc} =
        ~q[
        defmodule Root do
          @attr Some.Other.Module
        end
      ]
        |> index()

      assert attribute.type == :module
      assert attribute.parent == module_def.ref
      assert attribute.subject == Some.Other.Module
      assert decorate(doc, attribute.range) =~ "  @attr «Some.Other.Module»"
    end

    test "can detect a module reference on the left side of a pattern match" do
      {:ok, [_module_def, module_ref], doc} =
        ~q[
        defmodule Root do
          def my_fn(arg) do
            Some.Module = arg
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Module
      assert decorate(doc, module_ref.range) =~ "«Some.Module» = arg"
    end

    test "can detect an aliased module reference on the left side of a pattern match" do
      {:ok, [_module_def, _alias, module_ref], doc} =
        ~q[
        defmodule Root do
          alias Some.Other.Thing
          def my_fn(arg) do
            Thing.Util = arg
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Other.Thing.Util
      assert decorate(doc, module_ref.range) =~ "    «Thing.Util» = arg"
    end

    test "can detect a module reference on the right side of a pattern match" do
      {:ok, [_module, module_ref], doc} =
        ~q[
        defmodule Root do
          def my_fn(arg) do
            arg = Some.Module
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Module
      assert decorate(doc, module_ref.range) =~ "arg = «Some.Module»"
    end

    test "can detect an aliased module reference on the right side of a pattern match" do
      {:ok, [_module_def, _alias, module_ref], doc} =
        ~q[
        defmodule Root do
          alias Some.Other.Thing
          def my_fn(arg) do
            arg = Thing.Util
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Other.Thing.Util
      assert decorate(doc, module_ref.range) =~ "    arg = «Thing.Util»"
    end

    test "can detect a module reference in a remote call" do
      {:ok, [_module, module_ref], doc} =
        ~q[
          defmodule RemoteCall do
          def my_fn do
            Some.Module.function()
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Module
      assert decorate(doc, module_ref.range) =~ "  «Some.Module».function()"
    end

    test "can detect a module reference in a function call's arguments" do
      {:ok, [_module, module_ref], doc} =
        ~q[
          defmodule FunCallArgs do
          def my_fn do
            function(Some.Module)
          end

          def function(_) do
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Module
      assert decorate(doc, module_ref.range) =~ "  function(«Some.Module»)"
    end

    test "can detect a module reference in a function's pattern match arguments" do
      {:ok, [_module, module_ref], doc} =
        ~q[
          defmodule FunCallArgs do
          def my_fn(arg = Some.Module) do
            arg
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Module
      assert decorate(doc, module_ref.range) =~ "def my_fn(arg = «Some.Module»)"
    end

    test "can detect a module reference in default parameters" do
      {:ok, [_module, module_ref], doc} =
        ~q[
          defmodule FunCallArgs do
          def my_fn(module \\ Some.Module) do
            module.foo()
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Module
      assert decorate(doc, module_ref.range) =~ ~S[def my_fn(module \\ «Some.Module»)]
    end

    test "can detect a module reference in map keys" do
      {:ok, [_module, module_ref], doc} =
        ~q[
          defmodule FunCallArgs do
          def my_fn do
            %{Some.Module => 1}
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Module
      assert decorate(doc, module_ref.range) =~ "%{«Some.Module» => 1}"
    end

    test "can detect a module reference in map values" do
      {:ok, [_module, module_ref], doc} =
        ~q[
          defmodule FunCallArgs do
          def my_fn do
            %{invalid: Some.Module}
          end
        end
      ]t
        |> index()

      assert module_ref.type == :module
      assert module_ref.subject == Some.Module
      assert decorate(doc, module_ref.range) =~ "%{invalid: «Some.Module»}"
    end

    test "can detect a module reference in an anonymous function call" do
      {:ok, [parent, ref], doc} =
        ~q[
        defmodule Parent do
          def outer_fn do
            fn ->
              Ref.To.Something
            end
          end
        end
      ]
        |> index()

      assert ref.type == :module
      assert ref.subject == Ref.To.Something
      refute ref.parent == parent.ref
      assert decorate(doc, ref.range) =~ "      «Ref.To.Something»"
    end
  end

  describe "multiple modules in one document" do
    test "have different refs" do
      {:ok, [first, second], _} =
        ~q[
          defmodule First do
          end

          defmodule Second do
          end
        ]
        |> index()

      assert first.parent == :root
      assert first.type == :module
      assert first.subtype == :definition
      assert first.subject == First

      assert second.parent == :root
      assert second.type == :module
      assert second.subtype == :definition
      assert second.subject == Second

      assert second.ref != first.ref
    end

    test "aren't nested" do
      {:ok, [first, second, third, fourth], _} =
        ~q[
          defmodule A.B.C do
            defstruct do
              field(:ok, :boolean)
            end
          end

          defmodule D.E.F do
            defstruct do
              field(:ok, :boolean)
            end
          end

          defmodule G.H.I do
            defstruct do
              field(:ok, :boolean)
            end
          end

          defmodule J.K.L do
            defstruct do
              field(:ok, :boolean)
            end
          end
        ]
        |> index()

      assert first.subject == A.B.C
      assert second.subject == D.E.F
      assert third.subject == G.H.I
      assert fourth.subject == J.K.L
    end
  end

  describe "nested modules" do
    test "have a parent/child relationship" do
      {:ok, [parent, child], _} =
        ~q[
        defmodule Parent do
          defmodule Child do
          end
        end
      ]
        |> index()

      assert parent.parent == :root
      assert parent.type == :module
      assert parent.subtype == :definition

      assert child.parent == parent.ref
      assert child.type == :module
      assert child.subtype == :definition
    end

    test "Have aliases resolved correctly" do
      {:ok, [_parent, _parent_alias, child, child_alias], _} =
        ~q[
        defmodule Parent do
          alias Something.Else

          defmodule Child do
            alias Else.Other
          end
        end
      ]
        |> index()

      assert child_alias.parent == child.ref
      assert child_alias.type == :module
      assert child_alias.subtype == :reference
      assert child_alias.subject == Something.Else.Other
    end
  end
end
