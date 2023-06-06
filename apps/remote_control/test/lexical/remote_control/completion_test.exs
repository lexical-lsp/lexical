defmodule Lexical.RemoteControl.CompletionTest do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.Completion

  import Lexical.Test.CursorSupport
  import Lexical.Test.CodeSigil

  use ExUnit.Case, async: true

  describe "struct_fields/2" do
    test "returns the field completion for current module" do
      source = ~q<
        defmodule Project.Issue do
          defstruct [:message]
          @type t :: %__MODULE__{|}
        end
      >

      [message] = struct_fields(source)
      assert message.name == :message
    end

    test "returns the field completions for aliased module" do
      source = ~q<
        defmodule Project.Issue do
          alias Project.Issue
          defstruct [:message]
          @type t :: %Issue{|}
        end
      >

      [message] = struct_fields(source)
      assert message.name == :message
    end

    test "returns [] when cursor is not in a struct" do
      source = ~q<
        defmodule Project.Issue do
          alias Project.Issue
          defstruct [:message]
          @type t :: %Issue{}|
        end
      >

      assert struct_fields(source) == []
    end

    test "returns the field completions when cursor is in the current module child's arguments" do
      source = ~q<
        defmodule Project do
          defmodule Issue do
            @type t :: %Issue{}
            defstruct [:message]
          end

          def message(%__MODULE__.Issue{|} = issue) do
            issue.message
          end
        end
      >

      [message] = struct_fields(source)
      assert message.name == :message
    end

    test "returns the field completion when cursor is in an alias child's arguments" do
      source = ~q<
        defmodule Project do
          defmodule Issue do
            defstruct [:message]
          end
        end

        defmodule MyModule do
          alias Project

          def message(%Project.Issue{|} = issue) do
            issue.message
          end
        end
      >

      [message] = struct_fields(source)
      assert message.name == :message
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
