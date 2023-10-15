defmodule Lexical.Server.CodeIntelligence.Completion.Translations.MacroTest do
  alias Lexical.Protocol.Types.Completion

  use Lexical.Test.Server.CompletionCase

  describe "Kernel* macros" do
    test "do/end only has a single completion", %{project: project} do
      assert [completion] = complete(project, "def my_thing do|")
      assert apply_completion(completion) == "def my_thing do\n  $0\nend"
      assert completion.label == "do/end block"
    end

    test "def only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("def|")
               |> fetch_completion("def ")

      assert %Completion.Item{} = completion
      assert completion.detail
    end

    test "def", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("def|")
               |> fetch_completion("def ")

      assert completion.detail
      assert completion.label == "def (Define a function)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "def ${1:name}($2) do\n  $0\nend\n"
    end

    test "defp only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defp|")
               |> fetch_completion("defp ")

      assert %Completion.Item{} = completion
    end

    test "defp", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defp|")
               |> fetch_completion("defp ")

      assert completion.detail
      assert completion.label == "defp (Define a private function)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "defp ${1:name}($2) do\n  $0\nend\n"
    end

    test "defmacro only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmacro|")
               |> fetch_completion("defmacro ")

      assert %Completion.Item{} = completion
      assert completion.detail
    end

    test "defmacro", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmacro|")
               |> fetch_completion("defmacro ")

      assert completion.detail
      assert completion.label == "defmacro (Define a macro)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "defmacro ${1:name}($2) do\n  $0\nend\n"
    end

    test "defmacrop only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmacrop|")
               |> fetch_completion("defmacrop ")

      assert %Completion.Item{} = completion
      assert completion.detail
    end

    test "defmacrop", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmacrop|")
               |> fetch_completion("defmacrop ")

      assert completion.detail
      assert completion.label == "defmacrop (Define a private macro)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "defmacrop ${1:name}($2) do\n  $0\nend\n"
    end

    test "defmodule only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmodule|")
               |> fetch_completion("defmodule ")

      assert completion.detail
      assert %Completion.Item{} = completion
    end

    test "defmodule for lib paths", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmodule|")
               |> fetch_completion("defmodule ")

      assert completion.detail
      assert completion.label == "defmodule (Define a module)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             defmodule ${1:File} do
               $0
             end
             """
    end

    test "defmodule for test paths", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmodule|", path: "test/foo/project/my_test.exs")
               |> fetch_completion("defmodule ")

      assert completion.detail
      assert completion.label == "defmodule (Define a module)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             defmodule ${1:Foo.Project.MyTest} do
               $0
             end
             """
    end

    test "defmodule for test/support paths", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmodule|", path: "test/support/path/to/file.ex")
               |> fetch_completion("defmodule ")

      assert completion.detail
      assert completion.label == "defmodule (Define a module)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             defmodule ${1:Path.To.File} do
               $0
             end
             """
    end

    test "defmodule for other paths", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defmodule|", path: "/this/is/another/path.ex")
               |> fetch_completion("defmodule ")

      assert completion.detail
      assert completion.label == "defmodule (Define a module)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             defmodule ${1:Path} do
               $0
             end
             """
    end

    test "defprotocol only has a single completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defprotocol|")
               |> fetch_completion("defprotocol ")

      assert %Completion.Item{} = completion
      assert completion.detail
    end

    test "defprotocol", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defprotocol|")
               |> fetch_completion("defprotocol ")

      assert completion.detail
      assert completion.label == "defprotocol (Define a protocol)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
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

      assert %Completion.Item{} = completion
    end

    test "defimpl returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defimpl|")
               |> fetch_completion("defimpl ")

      assert completion.detail
      assert completion.label == "defimpl (Define a protocol implementation)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             defimpl ${1:protocol name}, for: ${2:type} do
               $0
             end
             """
    end

    test "defoverridable returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defoverridable|")
               |> fetch_completion("defoverridable ")

      assert completion.detail
      assert completion.label == "defoverridable (Mark a function as overridable)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == "defoverridable ${1:keyword or behaviour} $0"
    end

    test "defdelegate returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defdelegate|")
               |> fetch_completion("defdelegate")

      assert completion.detail
      assert completion.label == "defdelegate (Define a delegate function)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "defdelegate ${1:call}, to: ${2:module} $0\n"
    end

    test "defguard returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defguard|")
               |> fetch_completion("defguard ")

      assert completion.detail
      assert completion.label == "defguard (Define a guard macro)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "defguard ${1:call} $0\n"
    end

    test "defguardp returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defguardp|")
               |> fetch_completion("defguardp")

      assert completion.detail
      assert completion.label == "defguardp (Define a private guard macro)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "defguardp ${1:call} $0\n"
    end

    test "defexception returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defexception|")
               |> fetch_completion("defexception")

      assert completion.detail
      assert completion.label == "defexception (Define an exception)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "defexception [${1:fields}] $0\n"
    end

    test "defstruct returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("defstruct|")
               |> fetch_completion("defstruct")

      assert completion.detail
      assert completion.label == "defstruct (Define a struct)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "defstruct [${1:fields}] $0\n"
    end

    test "alias returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("alias|")
               |> fetch_completion("alias ")

      assert completion.detail
      assert completion.label == "alias (alias a module's name)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "alias $0"
    end

    test "use returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("us|")
               |> fetch_completion("use ")

      assert completion.label == "use (invoke another module's __using__ macro)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "use $0"
    end

    test "import returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("import|")
               |> fetch_completion("import")

      assert completion.detail
      assert completion.label == "import (import a module's functions)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "import $0"
    end

    test "require returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("require|")
               |> fetch_completion("require")

      assert completion.detail
      assert completion.label == "require (require a module's macros)"
      assert completion.insert_text_format == :snippet
      assert apply_completion(completion) == "require $0"
    end

    test "quote returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("quote|")
               |> fetch_completion("quote")

      assert completion.detail
      assert completion.label == "quote (quote block)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             quote ${1:options} do
               $0
             end
             """
    end

    test "receive returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("receive|")
               |> fetch_completion("receive")

      assert completion.detail
      assert completion.label == "receive (receive block)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             receive do
               ${1:message shape} -> $0
             end
             """
    end

    test "try returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("try|")
               |> fetch_completion("try")

      assert completion.detail
      assert completion.label == "try (try / catch / rescue block)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             try do
               $0
             end
             """
    end

    test "with returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("with|")
               |> fetch_completion("with")

      assert completion.detail
      assert completion.label == "with block"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             with ${1:match} do
               $0
             end
             """
    end

    test "if returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("if|")
               |> fetch_completion("if")

      assert completion.detail
      assert completion.label == "if (If statement)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             if ${1:test} do
               $0
             end
             """
    end

    test "unless returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("unless|")
               |> fetch_completion("unless")

      assert completion.detail
      assert completion.label == "unless (Unless statement)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             unless ${1:test} do
               $0
             end
             """
    end

    test "case returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("case|")
               |> fetch_completion("case")

      assert completion.detail
      assert completion.label == "case (Case statement)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             case ${1:test} do
               ${2:match} -> $0
             end
             """
    end

    test "cond returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("cond|")
               |> fetch_completion("cond")

      assert completion.detail
      assert completion.label == "cond (Cond statement)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             cond do
               ${1:test} ->
                 $0
             end
             """
    end

    test "for returns a snippet", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("for|")
               |> fetch_completion("for")

      assert completion.detail
      assert completion.label == "for (comprehension)"
      assert completion.insert_text_format == :snippet

      assert apply_completion(completion) == """
             for ${1:match} <- ${2:enumerable} do
               $0
             end
             """
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

  describe "Kernel.SpecialForms dunder completions" do
    test "__MODULE__ is suggested", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("__|")
               |> fetch_completion("__MODULE__")

      assert completion.detail
      assert completion.label == "__MODULE__"
      assert completion.kind == :constant
    end

    test "__DIR__ is suggested", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("__|")
               |> fetch_completion("__DIR__")

      assert completion.detail
      assert completion.label == "__DIR__"
      assert completion.kind == :constant
    end

    test "__ENV__ is suggested", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("__|")
               |> fetch_completion("__ENV__")

      assert completion.detail
      assert completion.label == "__ENV__"
      assert completion.kind == :constant
    end

    test "__CALLER__ is suggested", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("__|")
               |> fetch_completion("__CALLER__")

      assert completion.detail
      assert completion.label == "__CALLER__"
      assert completion.kind == :constant
    end

    test "__STACKTRACE__ is suggested", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("__|")
               |> fetch_completion("__STACKTRACE__")

      assert completion.detail
      assert completion.label == "__STACKTRACE__"
      assert completion.kind == :constant
    end

    test "__aliases__ is hidden", %{project: project} do
      assert [] = complete(project, "__aliases|")
    end

    test "__block__ is hidden", %{project: project} do
      assert [] = complete(project, "__block|")
    end
  end

  describe "normal macro completion" do
    test "completes imported macros", %{project: project} do
      source = ~q[
        import Project.Macros

        macro_a|
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :function)

      assert completion.kind == :function
      assert completion.insert_text_format == :snippet
      assert completion.label == "macro_add(a, b)"

      assert apply_completion(completion) =~ "macro_add(${1:a}, ${2:b})"
    end

    test "completes required macros", %{project: project} do
      source = ~q[
        require Project.Macros

        Project.Macros.macro_a|
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :function)

      assert completion.kind == :function
      assert completion.insert_text_format == :snippet
      assert completion.label == "macro_add(a, b)"

      assert apply_completion(completion) =~ "Project.Macros.macro_add(${1:a}, ${2:b})"
    end

    test "completes aliased macros", %{project: project} do
      source = ~q[
        alias Project.Macros
        require Macros

        Macros.macro_a|
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :function)

      assert completion.kind == :function
      assert completion.insert_text_format == :snippet
      assert completion.label == "macro_add(a, b)"

      assert apply_completion(completion) =~ "Macros.macro_add(${1:a}, ${2:b})"
    end
  end

  describe "sort_text" do
    test "dunder macros aren't boosted", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Project.__dunder_macro__|")
               |> fetch_completion("__dunder_macro__")

      refute boosted?(completion)
    end
  end

  test "test completion snippets", %{project: project} do
    assert {:ok, [stub, with_body, with_context | _ignored]} =
             project
             |> complete(inside_exunit_context("test|"))
             |> fetch_completion("test ")

    assert ~S(test "message"           ) = stub.label
    assert "A stub test" = stub.detail
    assert :snippet = stub.insert_text_format
    assert apply_completion(stub) == inside_exunit_context("test \"${0:message}\"\n")

    assert ~S(test "message" do...     ) = with_body.label
    assert "A test" = with_body.detail
    assert :snippet = with_body.insert_text_format

    assert apply_completion(with_body) ==
             inside_exunit_context("test \"${1:message}\" do\n  $0\nend\n")

    assert ~S(test "message", %{} do...) = with_context.label
    assert "A test that receives context" = with_context.detail
    assert :snippet = with_context.insert_text_format

    assert apply_completion(with_context) ==
             inside_exunit_context("test \"${1:message}\", %{${2:context}} do\n  $0\nend\n")
  end

  test "describe blocks", %{project: project} do
    assert {:ok, describe} =
             project
             |> complete(inside_exunit_context("descr|"))
             |> fetch_completion("describe ")

    assert describe.label == "describe \"message\""
    assert describe.insert_text_format == :snippet

    assert apply_completion(describe) ==
             inside_exunit_context("describe \"${1:message}\" do\n  $0\nend\n")
  end

  test "syntax macros", %{project: project} do
    assert [] = complete(project, "a =|")
    assert [] = complete(project, "a ==|")
    assert [] = complete(project, "a ..|")
    assert [] = complete(project, "a !|")
    assert [] = complete(project, "a !=|")
    assert [] = complete(project, "a !==|")
    assert [] = complete(project, "a &&|")
  end

  defp inside_exunit_context(text) do
    """
    defmodule Test do
      use ExUnit.Case

      #{text}
    """
  end
end
