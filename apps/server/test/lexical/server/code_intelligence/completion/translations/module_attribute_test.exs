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
      assert snippet_completion.insert_text == "@moduledoc \"\"\"\n      $0\n      \"\"\""
      assert snippet_completion.label == "@moduledoc"

      assert empty_completion.detail
      assert empty_completion.insert_text == "@moduledoc false"
      assert empty_completion.label == "@moduledoc"
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
      assert snippet_completion.insert_text == "@doc \"\"\"\n      $0\n      \"\"\""
      assert snippet_completion.label == "@doc"
      assert snippet_completion.kind == :property

      assert empty_completion.detail
      assert empty_completion.insert_text == "@doc false"
      assert empty_completion.label == "@doc"
      assert empty_completion.kind == :property
    end
  end
end
