defmodule Lexical.RemoteControl.CodeIntelligence.SymbolsTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.CodeIntelligence.Symbols
  use ExUnit.Case

  import Lexical.Test.CodeSigil
  import Lexical.Test.RangeSupport

  def document_symbols(code) do
    doc = Document.new("file:///file.ex", code, 1)
    symbols = Symbols.for_document(doc)
    {symbols, doc}
  end

  defp in_a_module(code) do
    """
    defmodule Parent do
      #{code}
    end
    """
  end

  test "a top level module is found" do
    {[%Symbols.Document{} = module], doc} =
      ~q[
      defmodule MyModule do
      end
      ]
      |> document_symbols()

    assert decorate(doc, module.detail_range) =~ "defmodule «MyModule» do"
    assert module.name == "MyModule"
    assert module.type == :module
  end

  test "multiple top-level modules are found" do
    {[first, second], doc} =
      ~q[
      defmodule First do
      end

      defmodule Second do
      end
      ]
      |> document_symbols()

    assert decorate(doc, first.detail_range) =~ "defmodule «First» do"
    assert first.name == "First"
    assert first.type == :module

    assert decorate(doc, second.detail_range) =~ "defmodule «Second» do"
    assert second.name == "Second"
    assert second.type == :module
  end

  test "nested modules are found" do
    {[outer], doc} =
      ~q[
      defmodule Outer do
        defmodule Inner do
          defmodule Innerinner do
          end
        end
      end
      ]
      |> document_symbols()

    assert decorate(doc, outer.detail_range) =~ "defmodule «Outer» do"
    assert outer.name == "Outer"
    assert outer.type == :module

    assert [inner] = outer.children
    assert decorate(doc, inner.detail_range) =~ "defmodule «Inner» do"
    assert inner.name == "Outer.Inner"
    assert inner.type == :module

    assert [inner_inner] = inner.children
    assert decorate(doc, inner_inner.detail_range) =~ "defmodule «Innerinner» do"
    assert inner_inner.name == "Outer.Inner.Innerinner"
    assert inner_inner.type == :module
  end

  test "module attribute definitions are found" do
    {[module], doc} =
      ~q[
      defmodule Module do
        @first 3
        @second 4
      end
      ]
      |> document_symbols()

    assert [first, second] = module.children
    assert decorate(doc, first.detail_range) =~ "  «@first 3»"
    assert first.name == "@first"

    assert decorate(doc, second.detail_range) =~ "  «@second 4»"
    assert second.name == "@second"
  end

  test "in-progress module attributes are skipped" do
    {[module], doc} =
      ~q[
      defmodule Module do
        @
        @callback foo() :: :ok
      end
      ]
      |> document_symbols()

    assert module.type == :module
    assert module.name == "Module"

    [callback] = module.children

    assert callback.type == :module_attribute
    assert callback.name == "@callback"
    assert callback.range == callback.detail_range
    assert decorate(doc, callback.range) =~ "«@callback foo() :: :ok»"
  end

  test "module attribute references are skipped" do
    {[module], _doc} =
      ~q[
        defmodule Parent do
         @attr 3
         def my_fun() do
          @attr
         end
        end

      ]
      |> document_symbols()

    [_attr_def, function_def] = module.children
    [] = function_def.children
  end

  test "public function definitions are found" do
    {[module], doc} =
      ~q[
      defmodule Module do
        def my_fn do
        end
      end
      ]
      |> document_symbols()

    assert [function] = module.children
    assert decorate(doc, function.detail_range) =~ " def «my_fn» do"
  end

  test "private function definitions are found" do
    {[module], doc} =
      ~q[
      defmodule Module do
        defp my_fn do
        end
      end
      ]
      |> document_symbols()

    assert [function] = module.children
    assert decorate(doc, function.detail_range) =~ " defp «my_fn» do"
    assert function.name == "my_fn"
  end

  test "struct definitions are found" do
    {[module], doc} =
      ~q{
      defmodule Module do
        defstruct [:name, :value]
      end
      }
      |> document_symbols()

    assert [struct] = module.children
    assert decorate(doc, struct.detail_range) =~ "  «defstruct [:name, :value]»"
    assert struct.name == "%Module{}"
    assert struct.type == :struct
  end

  test "struct references are skippedd" do
    assert {[], _doc} =
             ~q[%OtherModule{}]
             |> document_symbols()
  end

  test "variable definitions are skipped" do
    {[module], _doc} =
      ~q[
      defmodule Module do
        defp my_fn do
          my_var = 3
        end
      end
      ]
      |> document_symbols()

    assert [function] = module.children
    assert [] = function.children
  end

  test "variable references are skipped" do
    {[module], _doc} =
      ~q[
      defmodule Module do
        defp my_fn do
          my_var = 3
          my_var
        end
      end
      ]
      |> document_symbols()

    assert [function] = module.children
    assert [] = function.children
  end

  test "guards shown in the name" do
    {[module], doc} =
      ~q[
      defmodule Module do
        def my_fun(x) when x > 0 do
        end
      end
      ]
      |> document_symbols()

    [fun] = module.children
    assert decorate(doc, fun.detail_range) =~ "  def «my_fun(x) when x > 0» do"
    assert fun.type == :public_function
    assert fun.name == "my_fun(x) when x > 0"
    assert [] == fun.children
  end

  test "types show only their name" do
    {[module], doc} =
      ~q[
       @type something :: :ok
      ]
      |> in_a_module()
      |> document_symbols()

    assert module.type == :module

    [type] = module.children
    assert decorate(doc, type.detail_range) =~ "«@type something :: :ok»"
    assert type.name == "@type something"
    assert type.type == :type
  end

  test "specs are ignored" do
    {[module], _doc} =
      ~q[
      @spec my_fun(integer()) :: :ok
      ]
      |> in_a_module()
      |> document_symbols()

    assert module.type == :module
  end

  test "docs are ignored" do
    assert {[module], _doc} =
             ~q[
                @doc """
                 Hello
                """
             ]
             |> in_a_module()
             |> document_symbols()

    assert module.type == :module
  end

  test "moduledocs are ignored" do
    assert {[module], _doc} =
             ~q[
                @moduledoc """
                 Hello
                """
             ]
             |> in_a_module()
             |> document_symbols()

    assert module.type == :module
  end

  test "derives are ignored" do
    assert {[module], _doc} =
             ~q[
               @derive {Something, other}
             ]
             |> in_a_module()
             |> document_symbols()

    assert module.type == :module
  end

  test "impl declarations are ignored" do
    assert {[module], _doc} =
             ~q[
              @impl GenServer
             ]
             |> in_a_module()
             |> document_symbols()

    assert module.type == :module
  end

  test "tags ignored" do
    assert {[module], _doc} =
             ~q[
              @tag :skip
             ]
             |> in_a_module()
             |> document_symbols()

    assert module.type == :module
  end
end
