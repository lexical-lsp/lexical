defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleAttributeTest do
  use Lexical.Test.Server.CompletionCase

  describe "module attributes" do
    test "@moduledoc completions", %{project: project} do
      source = ~q[
        defmodule Docs do
          @modu|
        end
      ]

      assert [snippet_completion, empty_completion] = complete(project, source)

      assert snippet_completion.detail
      assert snippet_completion.label == "@moduledoc"

      # note: indentation should be correctly adjusted by editor
      assert apply_completion(snippet_completion) == ~q[
        defmodule Docs do
          @moduledoc """
        $0
        """
        end
      ]

      assert empty_completion.detail
      assert empty_completion.label == "@moduledoc"

      assert apply_completion(empty_completion) == ~q[
        defmodule Docs do
          @moduledoc false
        end
      ]
    end

    test "@doc completions", %{project: project} do
      source = ~q[
        defmodule MyModule do
          @d|
          def other_thing do
          end
        end
      ]

      assert {:ok, [snippet_completion, empty_completion]} =
               project
               |> complete(source)
               |> fetch_completion(kind: :property)

      assert snippet_completion.detail
      assert snippet_completion.label == "@doc"
      assert snippet_completion.kind == :property

      # note: indentation should be correctly adjusted by editor
      assert apply_completion(snippet_completion) == ~q[
        defmodule MyModule do
          @doc """
        $0
        """
          def other_thing do
          end
        end
      ]

      assert empty_completion.detail
      assert empty_completion.label == "@doc"
      assert empty_completion.kind == :property

      assert apply_completion(empty_completion) == ~q[
        defmodule MyModule do
          @doc false
          def other_thing do
          end
        end
      ]
    end

    test "local attribute completion with prefix", %{project: project} do
      source = ~q[
        defmodule Attr do
          @my_attribute :foo
          @my_|
        end
      ]

      assert [completion] = complete(project, source)
      assert completion.label == "@my_attribute"

      assert apply_completion(completion) == ~q[
        defmodule Attr do
          @my_attribute :foo
          @my_attribute
        end
      ]
    end

    test "local attribute completion immediately after @", %{project: project} do
      source = ~q[
        defmodule Attr do
          @my_attribute :foo
          @|
        end
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion("@my_attribute")

      assert completion.label == "@my_attribute"

      assert apply_completion(completion) == ~q[
        defmodule Attr do
          @my_attribute :foo
          @my_attribute
        end
      ]
    end
  end
end
