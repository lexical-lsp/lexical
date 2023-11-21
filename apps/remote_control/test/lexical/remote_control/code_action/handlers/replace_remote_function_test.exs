defmodule Lexical.RemoteControl.CodeAction.Handlers.ReplaceRemoteFunctionTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.CodeAction.Diagnostic
  alias Lexical.RemoteControl.CodeAction.Handlers.ReplaceRemoteFunction

  use Lexical.Test.CodeMod.Case

  setup do
    start_supervised!({Document.Store, derive: [analysis: &Lexical.Ast.analyze/1]})
    :ok
  end

  def apply_code_mod(original_text, _ast, options) do
    line_number = Keyword.get(options, :line, 1)

    suggestion =
      options
      |> Keyword.get(:suggestion, :count)
      |> Atom.to_string()

    :ok = Document.Store.open("file:///file.ex", original_text, 0)
    {:ok, document} = Document.Store.fetch("file:///file.ex")

    message =
      """
      warning: Enum.counts/1 is undefined or private. Did you mean:

            * concat/1
            * concat/2
            * count/1
            * count/2
      """
      |> String.trim()

    range =
      Document.Range.new(
        Document.Position.new(document, line_number, 0),
        Document.Position.new(document, line_number + 1, 0)
      )

    diagnostic = Diagnostic.new(range, message, nil)

    changes =
      document
      |> ReplaceRemoteFunction.actions(range, [diagnostic])
      |> Enum.flat_map(& &1.changes.edits)
      |> Enum.filter(fn
        %Lexical.Document.Edit{text: ^suggestion} -> true
        _ -> false
      end)

    {:ok, changes}
  end

  describe "fixes function call" do
    test "applied to a standalone call" do
      {:ok, result} =
        ~q{
          Enum.counts([1, 2, 3])
        }
        |> modify()

      assert result == "Enum.count([1, 2, 3])"
    end

    test "applied to a variable match" do
      {:ok, result} =
        ~q{
          x = Enum.counts([1, 2, 3])
        }
        |> modify()

      assert result == "x = Enum.count([1, 2, 3])"
    end

    test "applied to a variable match, preserves comments" do
      {:ok, result} =
        ~q{
          x = Enum.counts([1, 2, 3]) # TODO: Fix this
        }
        |> modify()

      assert result == "x = Enum.count([1, 2, 3]) # TODO: Fix this"
    end

    test "not changing variable name" do
      {:ok, result} =
        ~q{
          counts = Enum.counts([1, 2, 3])
        }
        |> modify()

      assert result == "counts = Enum.count([1, 2, 3])"
    end

    test "applied to a call after a pipe" do
      {:ok, result} =
        ~q{
          [1, 2, 3] |> Enum.counts()
        }
        |> modify()

      assert result == "[1, 2, 3] |> Enum.count()"
    end

    test "changing only a function from provided possible modules" do
      {:ok, result} =
        ~q{
          Enumerable.counts([1, 2, 3]) + Enum.counts([3, 2, 1])
        }
        |> modify()

      assert result == "Enumerable.counts([1, 2, 3]) + Enum.count([3, 2, 1])"
    end

    test "changing all occurrences of the function in the line" do
      {:ok, result} =
        ~q{
          Enum.counts([1, 2, 3]) + Enum.counts([3, 2, 1])
        }
        |> modify()

      assert result == "Enum.count([1, 2, 3]) + Enum.count([3, 2, 1])"
    end

    test "applied in a comprehension" do
      {:ok, result} =
        ~q{
          for x <- Enum.counts([[1], [2], [3]]), do: x
        }
        |> modify(suggestion: :concat)

      assert result == "for x <- Enum.concat([[1], [2], [3]]), do: x"
    end

    test "applied in a with block" do
      {:ok, result} =
        ~q{
          with x <- Enum.counts([1, 2, 3]), do: x
        }
        |> modify()

      assert result == "with x <- Enum.count([1, 2, 3]), do: x"
    end

    test "preserving the leading indent" do
      {:ok, result} = modify("     Enum.counts([1, 2, 3])", trim: false)

      assert result == "     Enum.count([1, 2, 3])"
    end
  end

  describe "fixes captured function" do
    test "applied to a standalone function" do
      {:ok, result} =
        ~q[
          &Enum.counts/1
        ]
        |> modify()

      assert result == "&Enum.count/1"
    end

    test "applied to a variable match" do
      {:ok, result} =
        ~q[
          x = &Enum.counts/1
        ]
        |> modify()

      assert result == "x = &Enum.count/1"
    end

    test "applied to a variable match, preserves comments" do
      {:ok, result} =
        ~q[
          x = &Enum.counts/1 # TODO: Fix this
        ]
        |> modify()

      assert result == "x = &Enum.count/1 # TODO: Fix this"
    end

    test "not changing variable name" do
      {:ok, result} =
        ~q{
          counts = &Enum.counts/1
        }
        |> modify()

      assert result == "counts = &Enum.count/1"
    end

    test "applied to an argument" do
      {:ok, result} =
        ~q{
          [[1, 2], [3, 4]] |> Enum.map(&Enum.counts/1)
        }
        |> modify()

      assert result == "[[1, 2], [3, 4]] |> Enum.map(&Enum.count/1)"
    end

    test "changing only a function from provided possible modules" do
      {:ok, result} =
        ~q{
          [&Enumerable.counts/1, &Enum.counts/1]
        }
        |> modify()

      assert result == "[&Enumerable.counts/1, &Enum.count/1]"
    end

    test "changing all occurrences of the function in the line" do
      {:ok, result} =
        ~q{
          [&Enum.counts/1, &Enum.counts/1]
        }
        |> modify()

      assert result == "[&Enum.count/1, &Enum.count/1]"
    end

    test "preserving the leading indent" do
      {:ok, result} = modify("     &Enum.counts/1", trim: false)

      assert result == "     &Enum.count/1"
    end
  end
end
