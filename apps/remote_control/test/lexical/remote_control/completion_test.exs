defmodule Lexical.RemoteControl.CompletionTest do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.Completion

  import Lexical.Test.CursorSupport
  import Lexical.Test.CodeSigil

  use ExUnit.Case, async: true

  describe "struct_fields/2" do
    test "it should move the cursor into struct arguments and return the correct fields" do
      source = ~q<
        defmodule Project.Issue do
          alias Project.Issue
          defstruct [:message]
          @type t :: %|Issue{}
        end
      >

      assert struct_fields(source) == [:message]
    end
  end

  defp document(source) do
    text = strip_cursor(source)
    Document.new(file_uri(), text, 1)
  end

  defp file_uri do
    "file:///elixir.ex"
  end

  defp position(source) do
    {line, column} = cursor_position(source)
    Position.new(line, column)
  end

  defp struct_fields(source) do
    document = document(source)
    position = position(source)
    text = Document.to_string(document)
    Code.compile_string(text)

    Completion.struct_fields(document, position)
  end
end
