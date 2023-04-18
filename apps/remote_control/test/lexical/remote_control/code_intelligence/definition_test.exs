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

  defp with_referenced_file(%{project: project}) do
    path = file_path(project, Path.join("lib", "my_definition.ex"))
    %{uri: SourceFile.Path.ensure_uri(path)}
  end

  defp uses_file_uri(project) do
    project
    |> file_path(Path.join("lib", "my_module.ex"))
    |> SourceFile.Path.ensure_uri()
  end

  defp open_uses_file(project, content) do
    uri = uses_file_uri(project)

    with :ok <- RemoteControl.call(project, SourceFile.Store, :open, [uri, content, 1]) do
      RemoteControl.call(project, SourceFile.Store, :fetch, [uri])
    end
  end

  setup_all do
    project = project(:navigations)
    {:ok, _, _} = RemoteControl.start_link(project, self())

    on_exit(fn ->
      :ok = RemoteControl.stop(project)
    end)

    RemoteControl.Api.schedule_compile(project, true)
    assert_receive project_compiled(), 5000

    %{project: project}
  end

  setup %{project: project} do
    uri = uses_file_uri(project)

    # NOTE: We need to make sure every tests start with fresh caller content file
    on_exit(fn ->
      :ok = RemoteControl.call(project, SourceFile.Store, :close, [uri])
    end)
  end

  describe "definition/2 when making remote call by alias" do
    setup [:with_referenced_file]

    test "find the definition of a remote function call", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_greet() do
            MyDefinition.greet|("World")
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    test "find the definition of the module", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_greet() do
            MyDefinition|.greet("World")
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[defmodule «MyDefinition» do]
    end

    test "find the macro definition", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_macro() do
            MyDefinition.print_hello|()
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  defmacro «print_hello» do]
    end

    test "it can't find the right arity function definition", %{project: project} do
      subject_module = ~q[
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
      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line == ~S[  def «sum»(a, b) do]
      assert referenced_uri =~ "navigations/lib/multi_arity.ex"
    end
  end

  describe "definition/2 when making remote call by import" do
    setup [:with_referenced_file]

    test "find the definition of a remote function call", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          import MyDefinition

          def uses_greet() do
            greet|("World")
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    test "find the definition of a remote macro call",
         %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          import MyDefinition

          def uses_macro() do
            print_hello|()
          end
        end
        ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  defmacro «print_hello» do]
    end
  end

  describe "definition/2 when making remote call by use to import definition" do
    setup [:with_referenced_file]

    test "find the function definition", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          use MyDefinition

          def uses_greet() do
            greet|("World")
          end
        end
        ]
      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    test "it can't find the correct definition when func defined in the quote block", %{
      project: project
    } do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          use MyDefinition

          def uses_hello_defined_in_using_quote() do
            hello_func_in_using|()
          end
        end
        ]
      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: this is wrong, it should go to the definition in the quote block
      # but it goes to the `use` keyword in the caller module
      # it can be fixed when we have a tracer, the tracer event kind will be `local_function`
      assert definition_line == ~S[  «use» MyDefinition]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end
  end

  describe "definition/2 when making local call" do
    test "find the function definition", %{project: project} do
      subject_module = ~q[
        defmodule UsesOwnFunction do
          def greet do
          end

          def uses_greet do
            greet|()
          end
        end
      ]

      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line == ~S[  def «greet» do]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    test "find the attribute", %{project: project} do
      subject_module = ~q[
        defmodule UsesAttribute do
          @b 2

          def use_attribute do
            @|b
          end
        end
        ]
      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line =~ ~S[«@b» 2]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    test "find the variable", %{project: project} do
      subject_module = ~q[
        defmodule UsesVariable do
          def use_variable do
            a = 1

            if true do
              a|
            end
          end
        end
      ]
      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line =~ ~S[«a» = 1]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    test "can't find the definition when calling a Elixir std module function",
         %{project: project} do
      subject_module = ~q[
        String.to_integer|("1")
      ]

      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: this should be fixed when we have a call tracer
      {:ok, nil} = definition(project, subject_module)
    end

    test "find the definition when calling a erlang module", %{project: project} do
      subject_module = ~q[
        :erlang.binary_to_atom|("1")
      ]
      {:ok, uri, definition_line} = definition(project, subject_module)

      assert uri =~ "/src/erlang.erl"
      assert definition_line =~ ~S[«binary_to_atom»(Binary)]
    end
  end

  defp caller_position(subject_module) do
    {line, character} = cursor_position(subject_module)
    Position.new(line, character)
  end

  defp definition(project, subject_module) do
    position = caller_position(subject_module)

    with {:ok, uses_file} <- open_uses_file(project, strip_cursor(subject_module)),
         {:ok, {source_file, range}} <-
           RemoteControl.Api.definition(project, uses_file, position),
         {:ok, definition_line} <- definition_line(source_file, range) do
      {:ok, source_file.uri, definition_line}
    end
  end

  defp definition_line(source_file, range) do
    with {:ok, line_text} <- SourceFile.fetch_text_at(source_file, range.start.line) do
      graphemes = String.graphemes(line_text)
      {text_before_range, range_text, text_after_range} = extract_range(graphemes, range)
      marked_text = mark_range(range_text)
      {:ok, IO.iodata_to_binary([text_before_range, marked_text, text_after_range])}
    end
  end

  defp extract_range(graphemes, range) do
    start_column = range.start.character - 1
    end_column = range.end.character - 1

    {text_before_range, remainder} = Enum.split(graphemes, start_column)
    {range_text, text_after_range} = Enum.split(remainder, end_column - start_column)
    {text_before_range, range_text, text_after_range}
  end

  @range_start_marker "«"
  @range_end_marker "»"

  defp mark_range(range_text) do
    [@range_start_marker | range_text ++ List.wrap(@range_end_marker)]
  end
end
