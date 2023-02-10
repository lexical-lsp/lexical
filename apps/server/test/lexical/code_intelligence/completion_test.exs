defmodule Lexical.CodeIntelligence.CompletionTest do
  alias Lexical.CodeIntelligence.Completion
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion.Context, as: CompletionContext
  alias Lexical.Protocol.Types.Completion.Item, as: CompletionItem
  alias Lexical.RemoteControl
  alias Lexical.SourceFile

  use ExUnit.Case

  import Lexical.Test.Fixtures

  setup_all do
    project = project()
    {:ok, _} = RemoteControl.start_link(project, self())
    {:ok, project: project}
  end

  def cursor_position(text) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({0, 0}, fn
      "|", line_and_column ->
        {:halt, line_and_column}

      "\n", {line, _} ->
        {:cont, {line + 1, 0}}

      _, {line, column} ->
        {:cont, {line, column + 1}}
    end)
  end

  def complete(project, text, context \\ nil) do
    {line, column} = cursor_position(text)
    root_path = Project.root_path(project)
    file_path = Path.join([root_path, "lib", "file.ex"])
    document = SourceFile.new("file://#{file_path}", text, 0)
    position = %SourceFile.Position{line: line, character: column}

    context =
      if is_nil(context) do
        CompletionContext.new(trigger_kind: :trigger_character)
      else
        context
      end

    Completion.complete(project, document, position, context)
  end

  def fetch_completion(completions, label_prefix) do
    case Enum.filter(completions, &String.starts_with?(&1.label, label_prefix)) do
      [] -> {:error, :not_found}
      [found] -> {:ok, found}
      found when is_list(found) -> {:ok, found}
    end
  end

  describe "excluding modules" do
    test "lexical modules are removed", %{project: project} do
      assert [] = complete(project, "Lexica|l")
    end

    test "Lexical submodules are removed", %{project: project} do
      assert [] = complete(project, "Lexical.RemoteContro|l")
    end

    test "Lexical functions are removed", %{project: project} do
      assert [] = complete(project, "Lexical.RemoteControl.|")
    end

    test "Dependency modules are removed", %{project: project} do
      assert [] = complete(project, "ElixirSense|")
    end

    test "Dependency functions are removed", %{project: project} do
      assert [] = complete(project, "Jason.encod|")
    end

    test "Dependency protocols are removed", %{project: project} do
      assert [] = complete(project, "Jason.Encode|")
    end

    test "Dependency structs are removed", %{project: project} do
      assert [] = complete(project, "Jason.Fragment|")
    end

    test "Dependency exceptions are removed", %{project: project} do
      assert [] = complete(project, "Jason.DecodeErro|")
    end
  end

  describe "single completions" do
    test "def only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("def|")
               |> fetch_completion("def ")

      assert %CompletionItem{} = completion
    end

    test "def", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("def|")
               |> fetch_completion("def ")

      assert completion.label == "def (Define a function)"
      assert completion.insert_text_format == :snippet
      assert completion.insert_text == "def ${1:name}($2) do\n  $0\nend\n"
    end

    test "defp only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defp|")
               |> fetch_completion("defp ")

      assert %CompletionItem{} = completion
    end

    test "defp", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defp|")
               |> fetch_completion("defp ")

      assert completion.label == "defp (Define a private function)"
      assert completion.insert_text_format == :snippet
      assert completion.insert_text == "defp ${1:name}($2) do\n  $0\nend\n"
    end

    test "defmacro only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmacro|")
               |> fetch_completion("defmacro ")

      assert %CompletionItem{} = completion
    end

    test "defmacro", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmacro|")
               |> fetch_completion("defmacro ")

      assert completion.label == "defmacro (Define a macro)"
      assert completion.insert_text_format == :snippet
      assert completion.insert_text == "defmacro ${1:name}($2) do\n  $0\nend\n"
    end

    test "defmacrop only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmacrop|")
               |> fetch_completion("defmacrop ")

      assert %CompletionItem{} = completion
    end

    test "defmacrop", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmacrop|")
               |> fetch_completion("defmacrop ")

      assert completion.label == "defmacrop (Define a private macro)"
      assert completion.insert_text_format == :snippet
      assert completion.insert_text == "defmacrop ${1:name}($2) do\n  $0\nend\n"
    end

    test "defmodule only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmodule|")
               |> fetch_completion("defmodule ")

      assert %CompletionItem{} = completion
    end

    test "defmodule", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmodule|")
               |> fetch_completion("defmodule ")

      assert completion.label == "defmodule (Define a module)"
      assert completion.insert_text_format == :snippet

      assert completion.insert_text == """
             defmodule ${1:module name} do
               $0
             end
             """
    end

    test "defprotocol only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defprotocol|")
               |> fetch_completion("defprotocol ")

      assert %CompletionItem{} = completion
    end

    test "defprotocol", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defprotocol|")
               |> fetch_completion("defprotocol ")

      assert completion.label == "defprotocol (Define a protocol)"
      assert completion.insert_text_format == :snippet

      assert completion.insert_text == """
             defprotocol ${1:protocol name} do
               $0
             end
             """
    end

    test "defimpl only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defimpl|")
               |> fetch_completion("defimpl ")

      assert %CompletionItem{} = completion
    end

    test "defimpl returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defimpl|")
               |> fetch_completion("defimpl ")

      assert completion.label == "defimpl (Define a protocol implementation)"
      assert completion.insert_text_format == :snippet

      assert completion.insert_text == ~S"""
             defimpl ${1:protocol name}, for: ${2:type} do
               $0
             end
             """
    end
  end
end
