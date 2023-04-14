defmodule Lexical.RemoteControl.CodeIntelligence.DefinitionTest do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position

  import Lexical.Test.Fixtures
  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport
  import Messages

  use ExUnit.Case, async: false

  defp with_navigation_project(_ctx) do
    project = project(:navigations)
    {:ok, _, _} = RemoteControl.start_link(project, self())

    on_exit(fn ->
      :ok = RemoteControl.stop(project)
    end)

    RemoteControl.Api.schedule_compile(project, true)
    assert_receive project_compiled(), 5000

    %{project: project}
  end

  defp with_referenced_file(%{project: project}, file \\ "my_definition.ex") do
    path = file_path(project, Path.join("lib", file))
    %{uri: SourceFile.Path.ensure_uri(path)}
  end

  defp open_uses_file(project, content) do
    uri =
      project
      |> file_path(Path.join("lib", "my_module.ex"))
      |> SourceFile.Path.ensure_uri()

    with :ok <- RemoteControl.call(project, SourceFile.Store, :open, [uri, content, 1]),
         {:ok, uses_file} <- RemoteControl.call(project, SourceFile.Store, :fetch, [uri]) do
      {:ok, uses_file}
    else
      {:error, :already_open} ->
        {:ok, uses_file} = RemoteControl.call(project, SourceFile.Store, :fetch, [uri])
        {:ok, uses_file}
    end
  end

  setup ~w(with_navigation_project)a

  describe "definition/2 when making remote call by alias" do
    setup [:with_referenced_file]

    test "find the definition of a remote function call", %{project: project, uri: referenced_uri} do
      uses_content = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_greet() do
            MyDefinition.greet|("World")
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, uses_content)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    test "find the definition of the module", %{project: project, uri: referenced_uri} do
      uses_content = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_greet() do
            MyDefinition|.greet("World")
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, uses_content)
      assert definition_line == ~S[defmodule «MyDefinition» do]
    end

    test "find the macro definition", %{project: project, uri: referenced_uri} do
      uses_content = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_macro() do
            MyDefinition.print_hello|()
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, uses_content)
      assert definition_line == ~S[  defmacro «print_hello» do]
    end

    test "it can't find the right arity function definition", %{project: project} do
      uses_content = ~q[
        defmodule UsesRemoteFunction do
          alias MultiArity

          def uses_multiple_arity_fun() do
            MultiArity.sum|(1, 2, 3)
          end
        end
        ]
      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: this is a limitation of elixir_sense
      # can be fixed when we have a tracer
      # when function is imported, it also has the issue
      {:ok, referenced_uri, definition_line} = definition(project, uses_content)

      assert definition_line == ~S[  def «sum»(a, b) do]
      assert referenced_uri =~ "navigations/lib/multi_arity.ex"
    end
  end

  describe "definition/2 when making remote call by import" do
    setup [:with_referenced_file]

    test "find the definition of a remote function call", %{project: project, uri: referenced_uri} do
      uses_content = ~q[
        defmodule UsesRemoteFunction do
          import MyDefinition

          def uses_greet() do
            greet|("World")
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, uses_content)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    test "find the definition of a remote macro call",
         %{project: project, uri: referenced_uri} do
      uses_content = ~q[
        defmodule UsesRemoteFunction do
          import MyDefinition

          def uses_macro() do
            print_hello|()
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, uses_content)
      assert definition_line == ~S[  defmacro «print_hello» do]
    end
  end

  describe "definition/2 when making remote call by use to import definition" do
    setup [:with_referenced_file]

    test "find the function definition", %{project: project, uri: referenced_uri} do
      uses_content = ~q[
        defmodule UsesRemoteFunction do
          use MyDefinition

          def uses_greet() do
            greet|("World")
          end
        end
        ]
      assert {:ok, ^referenced_uri, definition_line} = definition(project, uses_content)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    test "it can't find the correct definition when func defined in the quote block", %{
      project: project
    } do
      uses_content = ~q[
        defmodule UsesRemoteFunction do
          use MyDefinition

          def uses_hello_defined_in_using_quote() do
            hello_func_in_using|()
          end
        end
        ]
      {:ok, referenced_uri, definition_line} = definition(project, uses_content)

      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: this is wrong, it should go to the definition in the quote block
      # but it goes to the `use` keyword in the caller module
      # it can be fixed when we have a tracer, the tracer event kind will be `local_function`
      assert definition_line == ~S[  «use» MyDefinition]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end
  end

  describe "definition/2 when making local call" do
    setup [:with_referenced_file]

    test "find the function definition", %{project: project} do
      uses_content = ~q[
        defmodule UsesOwnFunction do
          def greet do
          end

          def uses_greet do
            greet|()
          end
        end
      ]

      {:ok, referenced_uri, definition_line} = definition(project, uses_content)

      assert definition_line == ~S[  def «greet» do]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    test "find the attribute", %{project: project} do
      uses_content = ~q[
        defmodule UsesAttribute do
          @b 2

          def use_attribute do
            @|b
          end
        end
        ]
      {:ok, referenced_uri, definition_line} = definition(project, uses_content)

      assert definition_line =~ ~S[«@b» 2]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    test "find the variable", %{project: project} do
      uses_content = ~q[
        defmodule UsesVariable do
          def use_variable do
            a = 1

            if true do
              a|
            end
          end
        end
      ]
      {:ok, referenced_uri, definition_line} = definition(project, uses_content)

      assert definition_line =~ ~S[«a» = 1]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    test "can't find the definition when call a Elixir std module function",
         %{project: project} do
      uses_content = ~q[
        String.to_integer|("1")
      ]

      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: this should be fixed when we have a call tracer
      {:ok, nil} = definition(project, uses_content)
    end

    test "find the definition when call a erlang module", %{project: project} do
      uses_content = ~q[
        :erlang.binary_to_atom|("1")
      ]
      {:ok, uri, definition_line} = definition(project, uses_content)

      assert uri =~ "/src/erlang.erl"
      assert definition_line =~ ~S[«binary_to_atom»(Binary)]
    end
  end

  defp caller_position(uses_content) do
    {line, character} = cursor_position(uses_content)
    Position.new(line, character)
  end

  defp definition(project, uses_content) do
    position = caller_position(uses_content)

    with {:ok, uses_file} = open_uses_file(project, strip_cursor(uses_content)),
         {:ok, {source_file, range}} <-
           RemoteControl.Api.definition(project, uses_file, position),
         {:ok, range_text} <- range_text(source_file, range) do
      {:ok, source_file.uri, range_text}
    end
  end

  defp range_text(source_file, range) do
    with {:ok, line_text} <- SourceFile.fetch_text_at(source_file, range.start.line) do
      start_column = range.start.character - 1
      end_column = range.end.character - 1
      end_symbol = ~s[»]
      start_symbol = ~s[«]

      graphemes = String.graphemes(line_text)
      original_text = Enum.slice(graphemes, start_column..(end_column - 1))
      text = [start_symbol | original_text ++ List.wrap(end_symbol)]

      {text_before_range, _} = Enum.split(graphemes, start_column)
      {_, text_after_range} = Enum.split(graphemes, end_column)
      {:ok, IO.iodata_to_binary(text_before_range ++ text ++ text_after_range)}
    end
  end
end
