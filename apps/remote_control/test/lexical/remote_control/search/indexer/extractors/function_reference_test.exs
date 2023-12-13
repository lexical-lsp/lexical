defmodule Lexical.RemoteControl.Search.Indexer.Extractors.FunctionReferenceTest do
  alias Lexical.Test.RangeSupport

  import Lexical.Test.CodeSigil
  import RangeSupport

  use Lexical.Test.ExtractorCase

  def index(source) do
    do_index(source, fn entry ->
      entry.type in [:function] and entry.subtype == :reference
    end)
  end

  describe "remote function references" do
    test "calling a zero-arg remote function with parens" do
      code = in_a_module_function("OtherModule.test()")

      {:ok, [reference], _} = index(code)

      assert reference.subject == "OtherModule.test/0"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "OtherModule.test()" = extract(code, reference.range)
    end

    test "calling a zero-arg remote function without parens" do
      code = in_a_module_function("OtherModule.test")

      {:ok, [reference], _} = index(code)
      assert reference.subject == "OtherModule.test/0"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "OtherModule.test" = extract(code, reference.range)
    end

    test "calling a one-arg remote function" do
      code = in_a_module_function("OtherModule.test(:arg)")

      {:ok, [reference], _} = index(code)
      assert reference.subject == "OtherModule.test/1"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "OtherModule.test(:arg)" = extract(code, reference.range)
    end

    test "calling a remote function that spans multiple lines" do
      code =
        """
        OtherModule.test(
        :first,
        :second,
        :third
        )
        """
        |> in_a_module_function()

      {:ok, [multi_line], _} = index(code)

      expected =
        """
        OtherModule.test(
        :first,
        :second,
        :third
        )
        """
        |> String.trim()

      assert multi_line.subject == "OtherModule.test/3"
      assert multi_line.type == :function
      assert multi_line.subtype == :reference
      assert expected == extract(code, multi_line.range)
    end
  end

  describe "aliased remote calls" do
    test "aliases are expanded" do
      code = ~q[
      defmodule Parent do
        alias Other.Long.Module
        def func do
          Module.function(a, b, c)
        end
      end
      ]

      {:ok, [reference], _} = index(code)

      assert reference.subject == "Other.Long.Module.function/3"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "Module.function(a, b, c)" == extract(code, reference.range)
    end

    test "aliases using as" do
      code = ~q[
      defmodule Parent do
        alias Other.Long.Module, as: Mod
        def func do
          Mod.function(a, b, c)
        end
      end
      ]

      {:ok, [reference], _} = index(code)

      assert reference.subject == "Other.Long.Module.function/3"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "Mod.function(a, b, c)" == extract(code, reference.range)
    end
  end

  describe "function captures" do
    test "with specified arity" do
      code = in_a_module_function("&OtherModule.test/3")
      {:ok, [reference], _} = index(code)

      assert reference.subject == "OtherModule.test/3"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "OtherModule.test/3" == extract(code, reference.range)
    end

    test "with anonymous arguments" do
      code = in_a_module_function("&OtherModule.test(arg, &1)")

      {:ok, [reference], _} = index(code)

      assert reference.subject == "OtherModule.test/2"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "OtherModule.test(arg, &1)" == extract(code, reference.range)
    end

    test "recognizes calls in a capture" do
      code = in_a_module("&OtherModule.test(to_string(&1))")
      {:ok, [outer_ref, inner_ref], _} = index(code)
      assert outer_ref.subject == "OtherModule.test/1"
      assert inner_ref.subject == "Kernel.to_string/1"
    end
  end

  describe "local function references" do
    test "finds a zero-arg local function on the right of a match" do
      code = in_a_module_function("x = local()")
      {:ok, [reference], _} = index(code)

      assert reference.subject == "Parent.local/0"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "local()" == extract(code, reference.range)
    end

    test "finds zero-arg local function with parens" do
      code = in_a_module_function("local()")

      {:ok, [reference], _} = index(code)
      assert reference.subject == "Parent.local/0"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "local()" == extract(code, reference.range)
    end

    test "finds multi-arg local function" do
      code = in_a_module_function("local(a, b, c)")

      {:ok, [reference], _} = index(code)
      assert reference.subject == "Parent.local/3"
      assert reference.type == :function
      assert reference.subtype == :reference
      assert "local(a, b, c)" == extract(code, reference.range)
    end

    test "finds multi-arg local function across multiple lines" do
      code =
        """
        my_thing = local_fn(
          first_arg,
          second_arg,
          third_arg
        )
        """
        |> in_a_module_function()

      {:ok, [reference], _} = index(code)
      assert reference.subject == "Parent.local_fn/3"
      assert reference.type == :function
      assert reference.subtype == :reference

      expected = ~q[
      local_fn(
      first_arg,
      second_arg,
      third_arg
      )
      ]t

      assert expected == extract(code, reference.range)
    end
  end

  describe "imported function references" do
    test "imported local functions remember their module" do
      code = ~q{
      defmodule Imports do
        import Enum, only: [each: 2]

        def function do
          each([1, 2], fn elem -> elem + 1 end)
        end
      end
      }

      assert {:ok, [reference], _} = index(code)
      assert reference.subject == "Enum.each/2"
      assert "each([1, 2], fn elem -> elem + 1 end)" = extract(code, reference.range)
    end

    test "are found even when captured" do
      code = ~q{
        import String, only: [downcase: 1]

        f = &downcase/1
      }

      assert {:ok, [downcase_reference], _} = index(code)
      assert downcase_reference.subject == "String.downcase/1"
      assert "downcase/1" == extract(code, downcase_reference.range)
    end

    test "works with multiple imports" do
      code = ~q{
        import Enum, only: [map: 2]
        import String, only: [downcase: 1]

        map(l, fn i -> downcase(i) end)
      }

      assert {:ok, [r1, r2], _} = index(code)
      assert r1.subject == "Enum.map/2"
      assert "map(l, fn i -> downcase(i) end)" = extract(code, r1.range)
      assert r2.subject == "String.downcase/1"
      assert "downcase(i)" = extract(code, r2.range)
    end
  end

  describe "dynamic invocations" do
    test "apply/3 with static arguments" do
      code = in_a_module_function("apply(OtherModule, :function_name, [1, 2, 3])")

      assert {:ok, [reference], _} = index(code)
      assert reference.subject == "OtherModule.function_name/3"
      assert "apply(OtherModule, :function_name, [1, 2, 3])" = extract(code, reference.range)
    end

    test "Kernel.apply/3 with static arguments" do
      code = in_a_module_function("Kernel.apply(OtherModule, :function_name, [1, 2, 3])")

      assert {:ok, [reference], _} = index(code)
      assert reference.subject == "OtherModule.function_name/3"

      assert "Kernel.apply(OtherModule, :function_name, [1, 2, 3])" =
               extract(code, reference.range)
    end
  end

  describe "exclusions" do
    @defs [
      def: 2,
      defp: 2,
      defdelegate: 2,
      defexception: 1,
      defguard: 1,
      defguardp: 1,
      defimpl: 3,
      defmacro: 2,
      defmacrop: 2,
      defmodule: 2,
      defoverridable: 1,
      defprotocol: 2,
      defstruct: 1
    ]

    for {fn_name, arity} <- @defs,
        args = Enum.map(0..arity, &"arg_#{&1}"),
        invocation = Enum.join(args, ", ") do
      test "#{fn_name} is not found" do
        assert {:ok, [], _} = index("#{unquote(fn_name)} #{unquote(invocation)}")
      end
    end

    @keywords ~w[and if import in not or raise require try use]
    for keyword <- @keywords do
      test "#{keyword} is not found" do
        assert {:ok, [], _} = index("#{unquote(keyword)}")
      end
    end

    @operators ~w[-> && ** ++ -- .. "..//" ! <> =~ @ |> | || * + - / != !== < <= == === > >=]
    for operator <- @operators do
      test "operator #{operator} is not found" do
        assert {:ok, [], _} = index("#{unquote(operator)}")
      end
    end
  end
end
