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
    Code.compile_file(path)
    %{uri: SourceFile.Path.ensure_uri(path)}
  end

  defp project_file_path(project, name) do
    file_path(project, Path.join("lib", name))
  end

  defp open_uses_file(project, content) do
    path = project_file_path(project, "my_module.ex")
    uri = SourceFile.Path.ensure_uri(path)
    :ok = SourceFile.Store.open(uri, content, 1)
    {:ok, uses_file} = SourceFile.Store.fetch(uri)
    uses_file
  end

  defp cursor_to_position(cursor, line, source_file) do
    {:ok, text} = SourceFile.fetch_text_at(source_file, line)
    [cursor | _] = String.split(cursor, "|", parts: 2)
    [before_cursor, _] = String.split(text, cursor, parts: 2)
    character = String.length(before_cursor) + String.length(cursor) + 1
    Position.new(line, character)
  end

  describe "definition/2 when making remote call by alias" do
    setup [:with_navigation_project, :with_referenced_file]

    setup do
      uses_content = ~q[
        defmodule MyModule do
          alias MyDefinition
          require MyDefinition

          def my_function() do
            MyDefinition.greet("World")
          end

          def uses_macro() do
            MyDefinition.print_hello()
          end
        end
        ]
      %{uses_content: uses_content}
    end

    test "find the definition of a remote function call", ctx do
      %{project: project, uri: referenced_uri, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("MyDefinition.gree|", 6, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          def greet(name) do
        #     ^^^^^
      ]

      assert source_file.uri == referenced_uri
    end

    test "find the definition of the module", ctx do
      %{project: project, uri: referenced_uri, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("MyDef|inition", 6, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        #         ^^^^^^^^^^^^
      ]

      assert source_file.uri == referenced_uri
    end

    test "find the macro definition", ctx do
      %{project: project, uri: referenced_uri, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("MyDefinition.print_hello|", 10, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          defmacro print_hello do
        #          ^^^^^^^^^^^
      ]

      assert source_file.uri == referenced_uri
    end
  end

  describe "definition/2 when making remote call by import" do
    setup [:with_navigation_project, :with_referenced_file]

    setup do
      uses_content = ~q[
        defmodule MyModule do
          import MyDefinition

          def my_function() do
            greet("World")
          end

          def uses_macro() do
            print_hello()
          end
        end
        ]

      %{uses_content: uses_content}
    end

    test "find the definition of a remote function call", ctx do
      %{project: project, uri: referenced_uri, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("greet|", 5, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          def greet(name) do
        #     ^^^^^
      ]

      assert source_file.uri == referenced_uri
    end

    test "find the definition of a remote macro call", ctx do
      %{project: project, uri: referenced_uri, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("print_hello|", 9, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          defmacro print_hello do
        #          ^^^^^^^^^^^
      ]

      assert source_file.uri == referenced_uri
    end
  end

  describe "definition/2 when making remote call by use to import definition" do
    setup [:with_navigation_project, :with_referenced_file]

    setup do
      uses_content = ~q[
        defmodule MyModule do
          use MyDefinition

          def my_function() do
            greet("World")
          end
        end
        ]

      %{uses_content: uses_content}
    end

    test "find the function definition", ctx do
      %{project: project, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("greet|", 5, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          def greet(name) do
        #     ^^^^^
      ]
    end
  end

  describe "definition/2 when making local call" do
    setup [:with_navigation_project, :with_referenced_file]

    test "find the function definition", ctx do
      %{uri: referenced_uri} = ctx

      {:ok, uses_file} = SourceFile.Store.open_temporary(referenced_uri)
      position = cursor_to_position("gree|", 22, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          def greet(name) do
        #     ^^^^^
      ]
    end

    test "find the attribute", ctx do
      %{uri: referenced_uri} = ctx

      {:ok, uses_file} = SourceFile.Store.open_temporary(referenced_uri)
      position = cursor_to_position("@|b", 37, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          @b 2
        # ^^
      ]
    end

    test "find the variable", ctx do
      %{uri: referenced_uri} = ctx

      {:ok, uses_file} = SourceFile.Store.open_temporary(referenced_uri)
      position = cursor_to_position("a|", 35, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

            a = 1
        #   ^
      ]
    end

    test "can't find the definition when call a Elixir std module function", ctx do
      {:ok, uses_file} = SourceFile.Store.open_temporary(ctx.uri)
      position = cursor_to_position("String.to_intege|", 42, uses_file)

      # TODO: this should be fixed when we have a call tracer
      {:ok, nil} = Definition.definition(uses_file, position)
    end

    test "find the definition when call a erlang module", ctx do
      {:ok, uses_file} = SourceFile.Store.open_temporary(ctx.uri)
      position = cursor_to_position("binary_to_|", 46, uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        %%
        ...

        binary_to_atom(Binary) ->
        ^^^^^^^^^^^^^^
      ]
    end
  end

  defp annotate(source_file, range) do
    {:ok, definition_line} = SourceFile.fetch_text_at(source_file, range.start.line)
    {:ok, module_header} = SourceFile.fetch_text_at(source_file, 1)

    module_part = Enum.join([module_header, "..."], "\n") <> "\n"

    annotation =
      if range.start.character <= 2 do
        # for erlang file
        String.duplicate("^", range.end.character - range.start.character)
      else
        "#" <>
          String.duplicate(" ", range.start.character - 2) <>
          String.duplicate("^", range.end.character - range.start.character)
      end

    if range.start.line == 1 do
      Enum.join([definition_line, annotation], "\n") <> "\n"
    else
      Enum.join([module_part, definition_line, annotation], "\n") <> "\n"
    end
  end
end
