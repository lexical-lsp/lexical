defmodule Lexical.RemoteControl.CodeIntelligence.DefinitionTest do
  alias Lexical.RemoteControl.CodeIntelligence.Definition

  import Lexical.Test.Fixtures
  import Lexical.Test.CodeSigil
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position

  use ExUnit.Case, async: false

  setup do
    start_supervised!(Lexical.SourceFile.Store)
    :ok
  end

  defp with_navigation_project(_ctx) do
    %{project: project(:navigations)}
  end

  defp with_referenced_file(%{project: project}) do
    path = file_path(project, Path.join("lib", "my_definition.ex"))
    %{uri: SourceFile.Path.ensure_uri(path)}
  end

  defp project_file_path(project, name) do
    file_path(project, Path.join("lib", name))
  end

  defp open_uses_file(project) do
    uses = ~q[
      defmodule MyModule do
        alias MyDefinition

        def my_function() do
          MyDefinition.greet()
        end
      end
      ]

    path = project_file_path(project, "my_module.ex")
    uri = SourceFile.Path.ensure_uri(path)

    :ok = SourceFile.Store.open(uri, uses, 1)
    {:ok, uses_file} = SourceFile.Store.fetch(uri)
    uses_file
  end

  defp cursor_to_position(cursor, line, source_file) do
    {:ok, text} = SourceFile.fetch_text_at(source_file, line)
    cursor = String.trim_trailing(cursor, "|")
    [before_cursor, _] = String.split(text, cursor, parts: 2)
    character = String.length(before_cursor) + String.length(cursor) + 1
    Position.new(line, character)
  end

  describe "definition/2" do
    setup [:with_navigation_project, :with_referenced_file]

    test "find the definition of a remote function call", %{project: project, uri: referenced_uri} do
      uses_file = open_uses_file(project)
      position = cursor_to_position("MyDefinition.gree|", 5, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          def greet(name) do
        #     ^^^^^
      ]

      assert source_file.uri == referenced_uri
    end
  end

  defp annotate(source_file, range) do
    {:ok, definition_line} = SourceFile.fetch_text_at(source_file, range.start.line)
    {:ok, module_header} = SourceFile.fetch_text_at(source_file, 1)

    module_part = module_header <> "\n" <> "..." <> "\n\n"

    definition_part =
      definition_line <>
        "\n" <>
        "#" <>
        String.duplicate(" ", range.start.character - 2) <>
        String.duplicate("^", range.end.character - range.start.character) <>
        "\n"

    module_part <> definition_part
  end
end
