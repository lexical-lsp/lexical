defmodule Lexical.Server.CodeIntelligence.DefinitionTest do
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Document.Position
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.ProjectNodeSupervisor
  alias Lexical.Server.CodeIntelligence.Definition

  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport
  import Lexical.Test.Fixtures
  import Messages

  use ExUnit.Case, async: false

  defp with_referenced_file(%{project: project}) do
    uri =
      project
      |> file_path(Path.join("lib", "my_definition.ex"))
      |> Document.Path.ensure_uri()

    %{uri: uri}
  end

  defp subject_module_uri(project) do
    project
    |> file_path(Path.join("lib", "my_module.ex"))
    |> Document.Path.ensure_uri()
  end

  defp subject_module(project, content) do
    uri = subject_module_uri(project)

    with :ok <- Document.Store.open(uri, content, 1) do
      Document.Store.fetch(uri)
    end
  end

  setup_all do
    start_supervised!(Lexical.Document.Store)

    project = project(:navigations)
    {:ok, _} = start_supervised({ProjectNodeSupervisor, project})
    {:ok, _, _} = RemoteControl.start_link(project, self())

    on_exit(fn ->
      :ok = RemoteControl.stop(project)
    end)

    RemoteControl.Api.schedule_compile(project, true)
    assert_receive project_compiled(), 5000

    %{project: project}
  end

  setup %{project: project} do
    uri = subject_module_uri(project)

    # NOTE: We need to make sure every tests start with fresh caller content file
    on_exit(fn ->
      :ok = Document.Store.close(uri)
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

    @doc """
    This is a limitation of the ElixirSense.
    It doesn't support finding the multiple arity definition when making remote call
    currently, it will always return the first definition.

    ## Example

      iex> defmodule MultiArity do
      ...>   def sum(a, b) do
      ...>     a + b
      ...>   end
      ...>
      ...>   def sum(a, b, c) do
      ...>     a + b + c
      ...>   end
      ...> end

    When we want to jump to the definition of `MultiArity.sum/3`,
    we will always go to the `MultiArity.sum/2`
    """
    @tag :skip
    test "find the right arity function definition", %{project: project} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          alias MultiArity

          def uses_multiple_arity_fun() do
            MultiArity.sum|(1, 2, 3)
          end
        end
        ]

      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line == ~S[  def «sum»(a, b, c) do]
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

    @doc """
    This is a limitation of the ElixirSense.
    like the `subject_module` below, it can't find the correct definition of `hello_func_in_using/0`
    when the definition module aliased by `use` or `import`,
    currently, it will go to the `use MyDefinition` line
    """
    @tag :skip
    test "find the correct definition when func defined in the quote block", %{
      project: project,
      uri: referenced_uri
    } do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          use MyDefinition

          def uses_hello_defined_in_using_quote() do
            hello_func_in_using|()
          end
        end
        ]
      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  def «hello_func_in_using» do]
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

    @doc """
    This is a limitation of the ElixirSense.
    like the `subject_module` below, it can't find the correct definition of `String.to_integer/1`,
    currently, it will always return `{:ok, nil}`
    """
    @tag :skip
    test "find the definition when calling a Elixir std module function",
         %{project: project} do
      subject_module = ~q[
        String.to_integer|("1")
      ]

      {:ok, uri, definition_line} = definition(project, subject_module)

      assert uri =~ "lib/elixir/lib/string.ex"
      assert definition_line =~ ~S[  def «to_integer»(string) when is_binary(string) do]
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

    with {:ok, subject_module_file} <- subject_module(project, strip_cursor(subject_module)),
         {:ok, %Location{} = location} <-
           Definition.definition(project, subject_module_file, position),
         {:ok, definition_line} <- definition_line(location.document, location.range) do
      {:ok, location.document.uri, definition_line}
    end
  end

  defp definition_line(document, range) do
    with {:ok, line_text} <- Document.fetch_text_at(document, range.start.line) do
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
