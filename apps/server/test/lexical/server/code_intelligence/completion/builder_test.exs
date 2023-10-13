defmodule Lexical.Server.CodeIntelligence.Completion.BuilderTest do
  alias Lexical.Ast.Env
  alias Lexical.Protocol.Types.Completion.Item, as: CompletionItem

  use ExUnit.Case, async: true

  import Lexical.Server.CodeIntelligence.Completion.Builder
  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport
  import Lexical.Test.Fixtures

  def new_env(text) do
    project = project()
    {position, document} = pop_cursor(text, as: :document)
    {:ok, env} = Env.new(project, document, position)
    env
  end

  def item(label, opts \\ []) do
    opts
    |> Keyword.merge(label: label)
    |> CompletionItem.new()
    |> boost(0)
  end

  defp sort_items(items) do
    Enum.sort_by(items, &{&1.sort_text, &1.label})
  end

  describe "boosting" do
    test "default boost sorts things first" do
      alpha_first = item("a")
      alpha_last = "z" |> item() |> boost()

      assert [^alpha_last, ^alpha_first] = sort_items([alpha_first, alpha_last])
    end

    test "local boost allows you to specify the order" do
      alpha_first = "a" |> item() |> boost(1)
      alpha_second = "b" |> item() |> boost(2)
      alpha_third = "c" |> item() |> boost(3)

      assert [^alpha_third, ^alpha_second, ^alpha_first] =
               sort_items([alpha_first, alpha_second, alpha_third])
    end

    test "global boost overrides local boost" do
      local_max = "a" |> item() |> boost(9)
      global_min = "z" |> item() |> boost(0, 1)

      assert [^global_min, ^local_max] = sort_items([local_max, global_min])
    end

    test "items can have a global and local boost" do
      group_b_min = "a" |> item() |> boost(1)
      group_b_max = "b" |> item() |> boost(2)
      group_a_min = "c" |> item |> boost(1, 1)
      group_a_max = "c" |> item() |> boost(2, 1)
      global_max = "d" |> item() |> boost(0, 2)

      items = [group_b_min, group_b_max, group_a_min, group_a_max, global_max]

      assert [^global_max, ^group_a_max, ^group_a_min, ^group_b_max, ^group_b_min] =
               sort_items(items)
    end
  end

  describe "strip_struct_operator_for_elixir_sense/1" do
    test "with a reference followed by  __" do
      {doc, _position} =
        "%__"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "__"
    end

    test "with a reference followed by a module name" do
      {doc, _position} =
        "%Module"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "Module"
    end

    test "with a reference followed by a module and a dot" do
      {doc, _position} =
        "%Module."
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "Module."
    end

    test "with a reference followed by a nested module" do
      {doc, _position} =
        "%Module.Sub"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "Module.Sub"
    end

    test "with a reference followed by an alias" do
      code = ~q[
        alias Something.Else
        %El|
      ]t

      {doc, _position} =
        code
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "alias Something.Else\nEl"
    end

    test "on a line with two references, replacing the first" do
      {doc, _position} =
        "%First{} = %Se"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "%First{} = Se"
    end

    test "on a line with two references, replacing the second" do
      {doc, _position} =
        "%Fir| = %Second{}"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "Fir = %Second{}"
    end

    test "with a plain module" do
      env = new_env("Module")
      {doc, _position} = strip_struct_operator_for_elixir_sense(env)

      assert doc == env.document
    end

    test "with a plain module strip_struct_reference a dot" do
      env = new_env("Module.")
      {doc, _position} = strip_struct_operator_for_elixir_sense(env)

      assert doc == env.document
    end

    test "leaves leading spaces in place" do
      {doc, _position} =
        "     %Some"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "     Some"
    end

    test "works in a function definition" do
      {doc, _position} =
        "def my_function(%Lo|)"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "def my_function(Lo)"
    end
  end
end
