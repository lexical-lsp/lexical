defmodule Lexical.RemoteControl.CodeIntelligence.DefinitionTest do
  alias Lexical.RemoteControl.CodeIntelligence.Definition
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Line
  alias Lexical.SourceFile.Position

  import Lexical.Test.Fixtures
  import Lexical.Test.CodeSigil
  import Line

  use ExUnit.Case, async: false

  setup do
    start_supervised!(Lexical.SourceFile.Store)
    Code.put_compiler_option(:ignore_module_conflict, true)
    :ok
  end

  defp with_navigation_project(_ctx) do
    %{project: project(:navigations)}
  end

  defp with_referenced_file(%{project: project}, file \\ "my_definition.ex") do
    path = file_path(project, Path.join("lib", file))
    Code.compile_file(path)
    %{uri: SourceFile.Path.ensure_uri(path)}
  end

  defp open_uses_file(project, content) do
    uri =
      project
      |> file_path(Path.join("lib", "my_module.ex"))
      |> SourceFile.Path.ensure_uri()

    with :ok <- SourceFile.Store.open(uri, content, 1),
         {:ok, uses_file} <- SourceFile.Store.fetch(uri) do
      uses_file
    end
  end

  defp cursor_to_position(cursor, source_file) do
    find_line = fn source_file, cursor ->
      Enum.find(Tuple.to_list(source_file.document.lines), fn line(text: text) ->
        cursor_full_text = String.replace(cursor, "|", "")
        String.contains?(text, cursor_full_text)
      end)
    end

    line(line_number: line_number) = find_line.(source_file, cursor)
    {:ok, text} = SourceFile.fetch_text_at(source_file, line_number)
    [cursor | _] = String.split(cursor, "|", parts: 2)
    [before_cursor, _] = String.split(text, cursor, parts: 2)
    character = String.length(before_cursor) + String.length(cursor) + 1
    Position.new(line_number, character)
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

          # elixir sense limitation
          alias MultiArity

          def uses_multiple_arity_fun() do
            MultiArity.sum(1, 2, 3)
          end
        end
        ]
      %{uses_content: uses_content}
    end

    test "find the definition of a remote function call", ctx do
      %{project: project, uri: referenced_uri, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("MyDefinition.gree|", uses_file)

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
      position = cursor_to_position("MyDef|inition", uses_file)

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
      position = cursor_to_position("MyDefinition.print_hello|", uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          defmacro print_hello do
        #          ^^^^^^^^^^^
      ]

      assert source_file.uri == referenced_uri
    end

    test "it can't find the right arity function definition", ctx do
      %{project: project, uses_content: uses_content} = ctx
      with_referenced_file(%{project: project}, "multi_arity.ex")

      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("MultiArity.sum|", uses_file)

      assert {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: this is a limitation of elixir_sense
      # can be fixed when we have a tracer
      # when function is imported, it also has the issue
      assert annotate(source_file, range) == ~q[
        defmodule MultiArity do
        ...

          def sum(a, b) do
        #     ^^^
      ]
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
      position = cursor_to_position("greet|", uses_file)

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
      position = cursor_to_position("print_hello|", uses_file)

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

          def uses_hello_defined_in_using_quote() do
            hello_func_in_using()
          end
        end
        ]

      %{uses_content: uses_content}
    end

    test "find the function definition", ctx do
      %{project: project, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("greet|", uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          def greet(name) do
        #     ^^^^^
      ]
    end

    test "it can't find the correct definition when func defined in the quote block", ctx do
      %{project: project, uses_content: uses_content} = ctx
      uses_file = open_uses_file(project, uses_content)
      position = cursor_to_position("hello|_func_in_using", uses_file)

      assert {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: this is wrong, it should go to the definition in the quote block
      # but it goes to the `use` keyword in the caller module
      # it can be fixed when we have a tracer, the tracer event kind will be `local_function`
      assert annotate(source_file, range) == ~q[
        defmodule MyModule do
        ...

          use MyDefinition
        # ^^^
      ]
    end
  end

  describe "definition/2 when making local call" do
    setup [:with_navigation_project, :with_referenced_file]

    test "find the function definition", ctx do
      {:ok, uses_file} = SourceFile.Store.open_temporary(ctx.uri)
      position = cursor_to_position(~s[greet|("world")], uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          def greet(name) do
        #     ^^^^^
      ]
    end

    test "find the attribute", ctx do
      {:ok, uses_file} = SourceFile.Store.open_temporary(ctx.uri)
      position = cursor_to_position("      @|b", uses_file)

      {:ok, {source_file, range}} = Definition.definition(uses_file, position)

      assert annotate(source_file, range) == ~q[
        defmodule MyDefinition do
        ...

          @b 2
        # ^^
      ]
    end

    test "find the variable", ctx do
      {:ok, uses_file} = SourceFile.Store.open_temporary(ctx.uri)
      position = cursor_to_position("      a|", uses_file)

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
      position = cursor_to_position("String.to_intege|", uses_file)

      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: this should be fixed when we have a call tracer
      {:ok, nil} = Definition.definition(uses_file, position)
    end

    test "find the definition when call a erlang module", ctx do
      {:ok, uses_file} = SourceFile.Store.open_temporary(ctx.uri)
      position = cursor_to_position("binary_to_|", uses_file)

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
