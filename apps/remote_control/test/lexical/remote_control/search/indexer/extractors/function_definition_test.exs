defmodule Lexical.RemoteControl.Search.Indexer.Extractors.FunctionDefinitionTest do
  use Lexical.Test.ExtractorCase

  def index(source) do
    do_index(source, fn entry ->
      entry.type in [:public_function, :private_function] and entry.subtype == :definition
    end)
  end

  def index_all(source) do
    do_index(source, fn entry ->
      entry.type in [:function, :public_function, :private_function]
    end)
  end

  describe "indexing public function definitions" do
    test "finds zero arity public functions (no parens)" do
      code =
        ~q[
          def zero_arity do
          end
        ]
        |> in_a_module()

      {:ok, [zero_arity], _} = index(code)

      assert zero_arity.type == :public_function
      assert zero_arity.subtype == :definition
      assert zero_arity.subject == "Parent.zero_arity/0"
      assert "def zero_arity do" == extract(code, zero_arity.range)
    end

    test "finds zero arity one line public functions (no parens)" do
      code =
        ~q[
          def zero_arity, do: true
        ]
        |> in_a_module()

      {:ok, [zero_arity], _} = index(code)

      assert zero_arity.type == :public_function
      assert zero_arity.subtype == :definition
      assert zero_arity.subject == "Parent.zero_arity/0"
      assert "def zero_arity, do" == extract(code, zero_arity.range)
    end

    test "finds zero arity public functions (with parens)" do
      code =
        ~q[
          def zero_arity() do
          end
        ]
        |> in_a_module()

      {:ok, [zero_arity], _} = index(code)

      assert zero_arity.type == :public_function
      assert zero_arity.subtype == :definition
      assert zero_arity.subject == "Parent.zero_arity/0"
      assert "def zero_arity() do" == extract(code, zero_arity.range)
    end

    test "finds one arity public function" do
      code =
        ~q[
          def one_arity(a) do
            a + 1
          end
        ]
        |> in_a_module()

      {:ok, [one_arity], _} = index(code)

      assert one_arity.type == :public_function
      assert one_arity.subtype == :definition
      assert one_arity.subject == "Parent.one_arity/1"
      assert "def one_arity(a) do" == extract(code, one_arity.range)
    end

    test "finds multi arity public function" do
      code =
        ~q[
          def multi_arity(a, b, c, d) do
            {a, b, c, d}
          end
        ]
        |> in_a_module()

      {:ok, [multi_arity], _} = index(code)

      assert multi_arity.type == :public_function
      assert multi_arity.subtype == :definition
      assert multi_arity.subject == "Parent.multi_arity/4"
      assert "def multi_arity(a, b, c, d) do" == extract(code, multi_arity.range)
    end

    test "finds multi-line function definitions" do
      code =
        ~q[
          def multi_line(a,
          b,
          c,
          d) do
          end
        ]
        |> in_a_module()

      {:ok, [multi_line], _} = index(code)

      expected =
        """
        def multi_line(a,
        b,
        c,
        d) do
        """
        |> String.trim()

      assert expected == extract(code, multi_line.range)
    end

    test "skips public functions defined in quote blocks" do
      code =
        ~q[
        def something(name) do
          quote do
            def unquote(name)() do
            end
          end
        end
        ]
        |> in_a_module()

      {:ok, [something], _} = index(code)
      assert "def something(name) do" = extract(code, something.range)
    end

    test "returns no references" do
      {:ok, [function_definition], doc} =
        ~q[
        def my_fn(a, b) do
        end
        ]
        |> in_a_module()
        |> index_all()

      assert function_definition.type == :public_function
      assert function_definition.subtype == :definition
      assert "def my_fn(a, b) do" = extract(doc, function_definition.range)
    end
  end

  describe "indexing private function definitions" do
    test "finds zero arity one-line private functions (no parens)" do
      code =
        ~q[
        defp zero_arity, do: true
      ]
        |> in_a_module()

      {:ok, [zero_arity], _} = index(code)

      assert zero_arity.type == :private_function
      assert zero_arity.subtype == :definition
      assert zero_arity.subject == "Parent.zero_arity/0"
      assert "defp zero_arity, do" == extract(code, zero_arity.range)
    end

    test "finds zero arity one-line private functions (with parens)" do
      code =
        ~q[
          defp zero_arity(), do: true
        ]
        |> in_a_module()

      {:ok, [zero_arity], _} = index(code)

      assert zero_arity.type == :private_function
      assert zero_arity.subtype == :definition
      assert zero_arity.subject == "Parent.zero_arity/0"
      assert "defp zero_arity(), do" == extract(code, zero_arity.range)
    end

    test "finds zero arity private functions (no parens)" do
      code =
        ~q[
          defp zero_arity do
          end
        ]
        |> in_a_module()

      {:ok, [zero_arity], _} = index(code)

      assert zero_arity.type == :private_function
      assert zero_arity.subtype == :definition
      assert zero_arity.subject == "Parent.zero_arity/0"
      assert "defp zero_arity do" == extract(code, zero_arity.range)
    end

    test "finds zero arity private functions (with parens)" do
      code =
        ~q[
          defp zero_arity() do
          end
        ]
        |> in_a_module()

      {:ok, [zero_arity], _} = index(code)

      assert zero_arity.type == :private_function
      assert zero_arity.subtype == :definition
      assert zero_arity.subject == "Parent.zero_arity/0"
      assert "defp zero_arity() do" == extract(code, zero_arity.range)
    end

    test "finds one arity one-line private functions" do
      code =
        ~q[
          defp one_arity(a), do: a + 1
        ]
        |> in_a_module()

      {:ok, [one_arity], _} = index(code)

      assert one_arity.type == :private_function
      assert one_arity.subtype == :definition
      assert one_arity.subject == "Parent.one_arity/1"
      assert "defp one_arity(a), do" == extract(code, one_arity.range)
    end

    test "finds one arity private functions" do
      code =
        ~q[
          defp one_arity(a) do
            a + 1
          end
        ]
        |> in_a_module()

      {:ok, [one_arity], _} = index(code)

      assert one_arity.type == :private_function
      assert one_arity.subtype == :definition
      assert one_arity.subject == "Parent.one_arity/1"
      assert "defp one_arity(a) do" == extract(code, one_arity.range)
    end

    test "finds multi-arity one-line private functions" do
      code =
        ~q[
          defp multi_arity(a, b, c), do: {a, b, c}
        ]
        |> in_a_module()

      {:ok, [one_arity], _} = index(code)

      assert one_arity.type == :private_function
      assert one_arity.subtype == :definition
      assert one_arity.subject == "Parent.multi_arity/3"
      assert "defp multi_arity(a, b, c), do" == extract(code, one_arity.range)
    end

    test "finds multi arity private functions" do
      code =
        ~q[
          defp multi_arity(a, b, c, d) do
            {a, b, c, d}
          end
        ]
        |> in_a_module()

      {:ok, [multi_arity], _} = index(code)

      assert multi_arity.type == :private_function
      assert multi_arity.subtype == :definition
      assert multi_arity.subject == "Parent.multi_arity/4"
      assert "defp multi_arity(a, b, c, d) do" == extract(code, multi_arity.range)
    end

    test "skips private functions defined in quote blocks" do
      code =
        ~q[
          defp something(name) do
            quote do
              defp unquote(name)() do

              end
            end
          end
        ]
        |> in_a_module()

      {:ok, [something], _} = index(code)
      assert "defp something(name) do" = extract(code, something.range)
    end

    test "returns no references" do
      {:ok, [function_definition], doc} =
        ~q[
        defp my_fn(a, b) do
        end
        ]
        |> in_a_module()
        |> index_all()

      assert function_definition.type == :private_function
      assert function_definition.subtype == :definition
      assert "defp my_fn(a, b) do" = extract(doc, function_definition.range)
    end
  end
end
