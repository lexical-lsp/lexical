defmodule Lexical.RemoteControl.Search.Indexer.SourceTest do
  alias Lexical.RemoteControl.Search.Indexer

  import Lexical.Test.CodeSigil

  use ExUnit.Case

  def index(source) do
    Indexer.Source.index("/foo/bar/baz.ex", source)
  end

  describe "indexing modules" do
    test "it doesn't confuse a list of atoms for a module" do
      {:ok, [module]} =
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
      {:ok, [entry]} =
        ~q[
        defmodule Simple do
        end
        ]
        |> index()

      assert entry.type == :module
      assert entry.parent == :root
      assert entry.start == {1, 1}
      assert entry.finish == {2, 1}
      assert entry.subject == Simple
    end

    test "indexes a flat module with a dotted name" do
      {:ok, [entry]} =
        ~q[
        defmodule Simple.Module.Path do
        end
        ]
        |> index()

      assert entry.subject == Simple.Module.Path
      assert entry.type == :module
      assert entry.parent == :root
      assert entry.start == {1, 1}
      assert entry.finish == {2, 1}
    end

    test "indexes a flat module with an aliased name" do
      {:ok, [_alias, entry]} =
        ~q[
        alias Something.Else
        defmodule Else.Other do
        end
      ]
        |> index()

      assert entry.subject == Something.Else.Other
    end

    test "can detect an erlang module" do
      {:ok, [module_def, erlang_module]} =
        ~q[
        defmodule Root do
          @something :timer
        end
      ]
        |> index()

      assert erlang_module.type == :module
      assert erlang_module.parent == module_def.ref
      assert erlang_module.subject == :timer
    end

    test "can detect a module reference in a module attribute" do
      {:ok, [module_def, attribute]} =
        ~q[
        defmodule Root do
          @attr Some.Other.Module
        end
      ]
        |> index()

      assert attribute.type == :module
      assert attribute.parent == module_def.ref
      assert attribute.subject == Some.Other.Module
      assert attribute.start == {2, 9}
      assert attribute.finish == {2, 20}
    end

    test "can detect a module reference on the left side of a pattern match" do
      {:ok, [_module_def, module_ref]} =
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
      assert module_ref.start == {3, 5}
      assert module_ref.finish == {3, 10}
    end

    test "can detect a module reference on the right side of a pattern match" do
      {:ok, [_module, module_ref]} =
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
      assert module_ref.start == {3, 11}
      assert module_ref.finish == {3, 16}
    end

    test "can detect a module reference in a remote call" do
      {:ok, [_module, module_ref]} =
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
      assert module_ref.start == {3, 3}
      assert module_ref.finish == {3, 8}
    end

    test "can detect a module reference in a function call's arguments" do
      {:ok, [_module, module_ref]} =
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
      assert module_ref.start == {3, 12}
      assert module_ref.finish == {3, 17}
    end

    test "can detect a module reference in a function's pattern match arguments" do
      {:ok, [_module, module_ref]} =
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
      assert module_ref.start == {2, 17}
      assert module_ref.finish == {2, 22}
    end

    test "can detect a module reference in default parameters" do
      {:ok, [_module, module_ref]} =
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
      assert module_ref.start == {2, 21}
      assert module_ref.finish == {2, 26}
    end

    test "can detect a module reference in map keys" do
      {:ok, [_module, module_ref]} =
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
      assert module_ref.start == {3, 5}
      assert module_ref.finish == {3, 10}
    end

    test "can detect a module reference in map values" do
      {:ok, [_module, module_ref]} =
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
      assert module_ref.start == {3, 14}
      assert module_ref.finish == {3, 19}
    end

    test "can detect a module reference in an anonymous function call" do
      {:ok, [parent, ref]} =
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
    end
  end

  describe "multiple modules in one document" do
    test "have different refs" do
      {:ok, [first, second]} =
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
  end

  describe "nested modules" do
    test "have a parent/child relationship" do
      {:ok, [parent, child]} =
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
      {:ok, [_parent, _parent_alias, child, child_alias]} =
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
