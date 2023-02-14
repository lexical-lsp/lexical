defmodule Lexical.CodeIntelligence.CompletionTest do
  alias Lexical.Server.Project.Dispatch
  alias Lexical.CodeIntelligence.Completion
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion.Context, as: CompletionContext
  alias Lexical.Protocol.Types.Completion.Item, as: CompletionItem
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.SourceFile

  use ExUnit.Case
  import Lexical.Test.Fixtures
  import RemoteControl.Api.Messages

  setup_all do
    project = project()

    {:ok, _} =
      start_supervised(
        {DynamicSupervisor, name: Server.Project.Supervisor.dynamic_supervisor_name()}
      )

    {:ok, _} = start_supervised({Server.Project.Supervisor, project})
    Dispatch.register(project, [project_compiled()])
    RemoteControl.Api.schedule_compile(project, true)
    assert_receive project_compiled(), 5000
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

  def complete(project, text, trigger_character \\ nil) do
    {line, column} = cursor_position(text)
    [text, _] = String.split(text, "|")
    root_path = Project.root_path(project)
    file_path = Path.join([root_path, "lib", "file.ex"])
    document = SourceFile.new("file://#{file_path}", text, 0)
    position = %SourceFile.Position{line: line, character: column}

    context =
      if is_binary(trigger_character) do
        CompletionContext.new(
          trigger_kind: :trigger_character,
          trigger_character: trigger_character
        )
      else
        CompletionContext.new(trigger_kind: :trigger_character)
      end

    Completion.complete(project, document, position, context)
  end

  def fetch_completion(completions, label_prefix) when is_binary(label_prefix) do
    case Enum.filter(completions, &String.starts_with?(&1.label, label_prefix)) do
      [] -> {:error, :not_found}
      [found] -> {:ok, found}
      found when is_list(found) -> {:ok, found}
    end
  end

  def fetch_completion(completions, opts) when is_list(opts) do
    matcher = fn completion ->
      Enum.reduce_while(opts, false, fn {key, value}, _ ->
        if Map.get(completion, key) == value do
          {:cont, true}
        else
          {:halt, false}
        end
      end)
    end

    case Enum.filter(completions, matcher) do
      [] -> {:error, :not_found}
      [found] -> {:ok, found}
      found when is_list(found) -> {:ok, found}
    end
  end

  describe "excluding modules from lexical dependencies" do
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

  test "ensure completion works for project", %{project: project} do
    refute [] == complete(project, "Project.|")
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

    test "defdelegate returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defdelegate|")
               |> fetch_completion("defdelegate")

      assert completion.label == "defdelegate (Define a delegate function)"
      assert completion.insert_text_format == :snippet

      assert completion.insert_text == ~S"""
             defdelegate ${1:call}, to: ${2:module} $0
             """
    end

    test "defguard returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defguard|")
               |> fetch_completion("defguard ")

      assert completion.label == "defguard (Define a guard macro)"
      assert completion.insert_text_format == :snippet

      assert completion.insert_text == ~S"""
             defguard ${1:call} $0
             """
    end

    test "defguardp returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defguardp|")
               |> fetch_completion("defguardp")

      assert completion.label == "defguardp (Define a private guard macro)"
      assert completion.insert_text_format == :snippet

      assert completion.insert_text == ~S"""
             defguardp ${1:call} $0
             """
    end

    test "defexception returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defexception|")
               |> fetch_completion("defexception")

      assert completion.label == "defexception (Define an exception)"
      assert completion.insert_text_format == :snippet

      assert completion.insert_text == ~S"""
             defexception [${1:fields}] $0
             """
    end

    test "deprecated functions are marked", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enum.filter_map|")
               |> fetch_completion("filter_map")

      assert [:deprecated] = completion.tags
    end

    test "__using__ is hidden", %{project: project} do
      assert [] == complete(project, "Project.__using__|")
    end

    test "__before_compile__ is hidden", %{project: project} do
      assert [] == complete(project, "Project.__before_compile__|")
    end

    test "__after_compile__ is hidden", %{project: project} do
      assert [] == complete(project, "Project.__after_compile__|")
    end
  end

  describe "sort_text" do
    test "dunder functions have the dunder removed in their sort_text", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enum.|")
               |> fetch_completion("__info__")

      assert completion.sort_text == "info/1"
    end

    test "dunder macros have the dunder removed in their sort_text", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Project.__dunder_macro__|")
               |> fetch_completion("__dunder_macro__")

      assert completion.sort_text == "dunder_macro/0"
    end
  end

  describe "structs" do
    test "should complete after %", %{project: project} do
      assert {:ok, [_, _] = account_and_user} =
               project
               |> complete("%Project.Structs.|")
               |> fetch_completion(kind: :struct)

      assert Enum.find(account_and_user, &(&1.label == "Account"))
      assert Enum.find(account_and_user, &(&1.label == "User"))
    end

    test "when using %, only parents of a struct are returned", %{project: project} do
      assert [completion] = complete(project, "%Project.|", "%")
      assert completion.label == "Structs"
      assert completion.kind == :module
    end

    test "when using %, only struct modules of are returned", %{project: project} do
      assert [_, _] = account_and_user = complete(project, "%Project.Structs.|", "%")
      assert Enum.find(account_and_user, &(&1.label == "Account"))
      assert Enum.find(account_and_user, &(&1.label == "User"))
    end

    test "it should complete struct fields", %{project: project} do
      assert fields =
               project
               |> complete("""
               alias Project.Structs.User
                 def my_function(%User{} = u) do
                   u.|
                 end
               end
               """)

      assert length(fields) == 3
      assert Enum.find(fields, &(&1.label == "first_name"))
      assert Enum.find(fields, &(&1.label == "last_name"))
      assert Enum.find(fields, &(&1.label == "email_address"))
    end
  end
end
