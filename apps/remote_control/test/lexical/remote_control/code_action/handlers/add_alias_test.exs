defmodule Lexical.RemoteControl.CodeAction.Handlers.AddAliasTest do
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.CodeUnit
  alias Lexical.Completion.SortScope
  alias Lexical.Document
  alias Lexical.Document.Line
  alias Lexical.Document.Range
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeAction.Handlers.AddAlias
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store

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
      case AddAlias.actions(document, range, []) do
        [action] -> action.changes.edits
        _ -> []
      end

    {:ok, edits}
  end

  def add_alias(original_text, modules_to_return) do
    {position, stripped_text} = pop_cursor(original_text)
    range = Range.new(position, position)
    patch_store(range, modules_to_return)
    modify(stripped_text, range: range)
  end

  def patch_store(range, modules_to_return) do
    returns =
      Enum.map(modules_to_return, fn
        %Entry{} = entry ->
          entry

        module ->
          %Entry{subject: module, range: range, type: :module, subtype: :definition}
      end)

    patch(Store, :fuzzy, {:ok, returns})
  end

  describe "in an existing module with no aliases" do
    test "aliases are added at the top of the module" do
      {:ok, added} =
        ~q[
        defmodule MyModule do
          def my_fn do
            Line|
          end
        end
        ]
        |> add_alias([Line])

      expected = ~q[
      defmodule MyModule do
        alias Lexical.Document.Line
        def my_fn do
          Line
        end
      end
      ]t
      assert added =~ expected
    end
  end

  describe "in an existing module" do
  end

  describe "in the root context" do
  end

  describe "adding an alias" do
    test "does nothing on an invalid document" do
      {:ok, added} = add_alias("%Lexical.RemoteControl.Search.", [Lexical.RemoteControl.Search])

      assert added == "%Lexical.RemoteControl.Search."
    end

    test "outside of a module with aliases" do
      {:ok, added} =
        ~q[
          alias ZZ.XX.YY
          Lines|
        ]
        |> add_alias([Line])

      expected = ~q[
      alias Lexical.Document.Line
      alias ZZ.XX.YY
      Lines
      ]t

      assert added == expected
    end

    test "when a full module name is given" do
      {:ok, added} =
        ~q[
        Lexical.RemoteControl.Search.Store.Backend|
        ]
        |> add_alias([Store.Backend])

      expected = ~q[
        alias Lexical.RemoteControl.Search.Store.Backend
        Backend
      ]t

      assert added == expected
    end

    test "when a full module name is given in a module function" do
      {:ok, added} =
        ~q[
        defmodule MyModule do
          def my_fun do
            result = Lexical.RemoteControl.Search.Store|
          end
        end
        ]
        |> add_alias([Store])

      expected = ~q[
        defmodule MyModule do
          alias Lexical.RemoteControl.Search.Store
          def my_fun do
            result = Store
          end
        end
      ]t

      assert added =~ expected
    end

    test "outside of a module with no aliases" do
      {:ok, added} =
        ~q[Lines|]
        |> add_alias([Line])

      expected = ~q[
       alias Lexical.Document.Line
       Lines
      ]t

      assert added == expected
    end

    test "in a module with no aliases" do
      {:ok, added} =
        ~q[
        defmodule MyModule do
          def my_fun do
            Line|
          end
        end
        ]
        |> add_alias([Line])

      expected = ~q[
      defmodule MyModule do
        alias Lexical.Document.Line
        def my_fun do
          Line
        end
      end
      ]t

      assert added =~ expected
    end

    test "outside of functions" do
      {:ok, added} =
        ~q[
        defmodule MyModule do
          alias Something.Else
          Lines|
        end
        ]
        |> add_alias([Line])

      expected = ~q[
      defmodule MyModule do
        alias Lexical.Document.Line
        alias Something.Else
        Lines
      end
      ]

      assert expected =~ added
    end

    test "inside a function" do
      {:ok, added} =
        ~q[
        defmodule MyModule do
          alias Something.Else
          def my_fn do
            Lines|
          end
        end
        ]
        |> add_alias([Line])

      expected = ~q[
      defmodule MyModule do
        alias Lexical.Document.Line
        alias Something.Else
        def my_fn do
          Lines
        end
      end
      ]
      assert expected =~ added
    end

    test "inside a nested module" do
      {:ok, added} =
        ~q[
          defmodule Parent do
            alias Top.Level
            defmodule Child do
              alias Some.Other
              Lines|
            end
          end
        ]
        |> add_alias([Line])

      expected = ~q[
      defmodule Parent do
        alias Top.Level
        defmodule Child do
          alias Lexical.Document.Line
          alias Some.Other
          Lines
        end
      end
      ]t

      assert added =~ expected
    end

    test "aliases for struct references don't include non-struct modules" do
      {:ok, added} = add_alias("%Scope|{}", [SortScope, Scope])

      expected = ~q[
      alias Lexical.Ast.Analysis.Scope
      %Scope
      ]t

      assert added =~ expected
    end

    test "only modules with a similarly named function will be included in aliases" do
      {:ok, added} = add_alias("Document.fetch|", [Document, RemoteControl])

      expected = ~q[
      alias Lexical.Document
      Document.fetch
      ]t

      assert added =~ expected
    end

    test "protocols are excluded" do
      {:ok, added} = add_alias("Co|", [Collectable, CodeUnit])
      expected = ~q[
      alias Lexical.CodeUnit
      Co
      ]t

      assert added =~ expected
    end
  end
end
