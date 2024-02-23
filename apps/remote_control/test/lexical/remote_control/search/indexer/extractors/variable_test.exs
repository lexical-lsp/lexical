defmodule Lexical.RemoteControl.Search.Indexer.Extractors.VariableTest do
  alias Lexical.RemoteControl.Search.Indexer.Extractors

  use Lexical.Test.ExtractorCase

  def index_references(source) do
    do_index(source, fn entry -> entry.type == :variable and entry.subtype == :reference end, [
      Extractors.Variable
    ])
  end

  def index_definitions(source) do
    do_index(source, fn entry -> entry.type == :variable and entry.subtype == :definition end, [
      Extractors.Variable
    ])
  end

  def assert_definition(entry, variable_name) do
    assert entry.type == :variable
    assert entry.subtype == :definition
    assert entry.subject == variable_name
  end

  def assert_reference(entry, variable_name) do
    assert entry.type == :variable
    assert entry.subtype == :reference
    assert entry.subject == variable_name
  end

  for def_type <- [:def, :defp, :defmacro, :defmacrop] do
    describe "variable definitions in #{def_type} parameters are extracted" do
      test "in a plain parameter" do
        {:ok, [param], doc} =
          ~q[
        #{unquote(def_type)} my_fun(var) do
        end
        ]
          |> index_definitions()

        assert_definition(param, :var)
        assert decorate(doc, param.range) =~ "#{unquote(def_type)} my_fun(«var»)"
      end

      test "in a struct value" do
        {:ok, [param], doc} =
          ~q[
        #{unquote(def_type)} my_fun(%Pattern{foo: var}) do
        end
        ]
          |> index_definitions()

        assert_definition(param, :var)
        assert decorate(doc, param.range) =~ "#{unquote(def_type)} my_fun(%Pattern{foo: «var»})"
      end

      test "on both sides of a pattern match" do
        {:ok, [var_1, var_2], doc} =
          ~q[
        #{unquote(def_type)} my_fun(%Pattern{foo: var} = var_2) do
        end
        ]
          |> index_definitions()

        assert_definition(var_1, :var)

        assert decorate(doc, var_1.range) =~
                 "#{unquote(def_type)} my_fun(%Pattern{foo: «var»} = var_2)"

        assert_definition(var_2, :var_2)

        assert decorate(doc, var_2.range) =~
                 "#{unquote(def_type)} my_fun(%Pattern{foo: var} = «var_2»)"
      end

      test "in a struct module" do
        {:ok, [var_1], doc} =
          ~q[
        #{unquote(def_type)} my_fun(%my_module{}) do
        end
        ]
          |> index_definitions()

        assert_definition(var_1, :my_module)
        assert decorate(doc, var_1.range) =~ "#{unquote(def_type)} my_fun(%«my_module»{})"
      end

      test "in list elements" do
        {:ok, [var_1, var_2], doc} =
          ~q{
        #{unquote(def_type)} my_fun([var_1, var_2]) do
        end
        }
          |> index_definitions()

        assert_definition(var_1, :var_1)
        assert decorate(doc, var_1.range) =~ "#{unquote(def_type)} my_fun([«var_1», var_2])"

        assert_definition(var_2, :var_2)
        assert decorate(doc, var_2.range) =~ "#{unquote(def_type)} my_fun([var_1, «var_2»])"
      end

      test "in the tail of a list" do
        {:ok, [tail], doc} =
          ~q{
        #{unquote(def_type)} my_fun([_ | acc]) do
        end
        }
          |> index_definitions()

        assert_definition(tail, :acc)
        assert decorate(doc, tail.range) =~ "#{unquote(def_type)} my_fun([_ | «acc»])"
      end

      test "unless it is an alias" do
        {:ok, [], _} =
          ~q[
            #{unquote(def_type)} my_fun(%MyStruct{}) do
            end
          ]
          |> index_definitions()
      end

      test "unless it begins with an underscore" do
        {:ok, [], _} =
          ~q[
            #{unquote(def_type)} my_fun(_unused) do
            end
          ]
          |> index_definitions()

        {:ok, [], _} =
          ~q[
            #{unquote(def_type)} my_fun(_) do
            end
          ]
          |> index_definitions()
      end
    end
  end

  describe "variable definitions in anonymous function parameters are extracted" do
    test "in a plain parameter" do
      {:ok, [param], doc} =
        ~q[
         fn var ->
          nil
         end
        ]
        |> index_definitions()

      assert_definition(param, :var)
      assert decorate(doc, param.range) =~ "fn «var» ->"
    end

    test "in a struct's values" do
      {:ok, [param], doc} =
        ~q[
        fn %Pattern{foo: var} ->
          nil
        end
        ]
        |> index_definitions()

      assert_definition(param, :var)
      assert decorate(doc, param.range) =~ "fn %Pattern{foo: «var»} ->"
    end

    test "when they're pinned" do
      {:ok, [param], doc} =
        ~q[
        fn ^pinned ->
          nil
        end
        ]
        |> index_definitions()

      assert_definition(param, :pinned)
      assert decorate(doc, param.range) =~ "fn ^«pinned» ->"
    end

    test "on both sides of a pattern match" do
      {:ok, [var_1, var_2], doc} =
        ~q[
        fn %Pattern{foo: var} = var_2 ->
          nil
        end
        ]
        |> index_definitions()

      assert_definition(var_1, :var)
      assert decorate(doc, var_1.range) =~ "fn %Pattern{foo: «var»} = var_2 ->"

      assert_definition(var_2, :var_2)
      assert decorate(doc, var_2.range) =~ "fn %Pattern{foo: var} = «var_2» ->"
    end

    test "in a struct module" do
      {:ok, [var_1], doc} =
        ~q[
        fn %my_module{} ->
          nil
        end
        ]
        |> index_definitions()

      assert_definition(var_1, :my_module)
      assert decorate(doc, var_1.range) =~ "fn %«my_module»{} ->"
    end

    test "in list elements" do
      {:ok, [var_1, var_2], doc} =
        ~q{
        fn [var_1, var_2] ->
          nil
        end
        }
        |> index_definitions()

      assert_definition(var_1, :var_1)
      assert decorate(doc, var_1.range) =~ "fn [«var_1», var_2] ->"

      assert_definition(var_2, :var_2)
      assert decorate(doc, var_2.range) =~ "fn [var_1, «var_2»] ->"
    end

    test "in the tail of a list" do
      {:ok, [tail], doc} =
        ~q{
         fn [_ | acc] ->
          nil
          end
        }
        |> index_definitions()

      assert_definition(tail, :acc)
      assert decorate(doc, tail.range) =~ "fn [_ | «acc»] ->"
    end

    test "unless it is an alias" do
      {:ok, [], _} =
        ~q[
        fn %MyStruct{} ->
          nil
        end
        ]
        |> index_definitions()
    end

    test "unless it starts with an underscore" do
      {:ok, [], _} =
        ~q[
        fn _unused ->
          nil
        end
        ]
        |> index_definitions()

      {:ok, [], _} =
        ~q[
        fn _ ->
          nil
        end
        ]
        |> index_definitions()
    end
  end

  describe "variable definitions in code are extracted" do
    test "from full pattern matches" do
      {:ok, [var], doc} = index_definitions(~q[var = 38])

      assert_definition(var, :var)
      assert decorate(doc, var.range) =~ "«var» = 38"
    end

    test "from tuples elements" do
      {:ok, [first, second], doc} = index_definitions(~q({first, second} = foo))

      assert_definition(first, :first)
      assert decorate(doc, first.range) =~ "{«first», second} ="

      assert_definition(second, :second)
      assert decorate(doc, second.range) =~ "{first, «second»} ="
    end

    test "from list elements" do
      {:ok, [first, second], doc} = index_definitions(~q([first, second] = foo))

      assert_definition(first, :first)
      assert decorate(doc, first.range) =~ "[«first», second] ="

      assert_definition(second, :second)
      assert decorate(doc, second.range) =~ "[first, «second»] ="
    end

    test "from  map values" do
      {:ok, [value], doc} = index_definitions(~q(%{key: value} = whatever))

      assert_definition(value, :value)
      assert decorate(doc, value.range) =~ "%{key: «value»} = whatever"
    end

    test "from struct values" do
      {:ok, [value], doc} = index_definitions(~q(%MyStruct{key: value} = whatever))

      assert_definition(value, :value)
      assert decorate(doc, value.range) =~ "%MyStruct{key: «value»} = whatever"
    end

    test "from  struct modules" do
      {:ok, [module], doc} = index_definitions(~q(%struct_module{} = whatever))

      assert_definition(module, :struct_module)
      assert decorate(doc, module.range) =~ "%«struct_module»{} = whatever"
    end

    test "from complex, nested mappings" do
      {:ok, [module, list_elem, tuple_first, tuple_second], doc} =
        index_definitions(
          ~q(%struct_module{key: [list_elem, {tuple_first, tuple_second}]} = whatever)
        )

      assert_definition(module, :struct_module)

      assert decorate(doc, module.range) =~
               "%«struct_module»{key: [list_elem, {tuple_first, tuple_second}]} = whatever"

      assert_definition(list_elem, :list_elem)

      assert decorate(doc, list_elem.range) =~
               "%struct_module{key: [«list_elem», {tuple_first, tuple_second}]} = whatever"

      assert_definition(tuple_first, :tuple_first)

      assert decorate(doc, tuple_first.range) =~
               "%struct_module{key: [list_elem, {«tuple_first», tuple_second}]} = whatever"

      assert_definition(tuple_second, :tuple_second)

      assert decorate(doc, tuple_second.range) =~
               "%struct_module{key: [list_elem, {tuple_first, «tuple_second»}]} = whatever"
    end
  end

  describe "variable references are extracted" do
    test "when by themselves" do
      assert {:ok, [ref], doc} = index_references(~q[variable])

      assert_reference(ref, :variable)
      assert decorate(doc, ref.range) =~ "«variable»"
    end

    test "from pinned variables" do
      {:ok, [ref], doc} = index_references("^pinned = 3")

      assert_reference(ref, :pinned)
      assert decorate(doc, ref.range) =~ "^«pinned» = 3"
    end

    test "on the left side of operators" do
      assert {:ok, [ref], doc} = index_references(~q[x + 3])

      assert_reference(ref, :x)
      assert decorate(doc, ref.range) =~ "«x» + 3"
    end

    test "on the right side of operators" do
      assert {:ok, [ref], doc} = index_references(~q[3 + x])

      assert_reference(ref, :x)
      assert decorate(doc, ref.range) =~ "3 + «x»"
    end

    test "on the right of pattern matches" do
      assert {:ok, [ref], doc} = index_references(~q[x = other_variable])

      assert_reference(ref, :other_variable)
      assert decorate(doc, ref.range) =~ "x = «other_variable»"
    end

    test "on the right side of pattern matches with dot notation" do
      assert {:ok, [ref], doc} = index_references(~q[x = foo.bar.baz])

      assert_reference(ref, :foo)
      assert decorate(doc, ref.range) =~ "x = «foo».bar.baz"
    end

    test "on the right side of a pattern match in a function call" do
      assert {:ok, [ref], doc} = index_references(~q[_ = foo(bar)])

      assert_reference(ref, :bar)
      assert decorate(doc, ref.range) =~ "_ = foo(«bar»)"
    end

    test "on the left of pattern matches via a pin" do
      assert {:ok, [ref], doc} = index_references(~q[^pin = 49])

      assert_reference(ref, :pin)
      assert decorate(doc, ref.range) =~ "^«pin» = 49"
    end

    test "from function call arguments" do
      assert {:ok, [ref], doc} = index_references(~q[pow(x, 3)])

      assert_reference(ref, :x)
      assert decorate(doc, ref.range) =~ "pow(«x», 3)"
    end

    test "when using access syntax" do
      assert {:ok, [ref], doc} = index_references(~q{3 = foo[:bar]})

      assert_reference(ref, :foo)
      assert decorate(doc, ref.range) =~ "3 = «foo»[:bar]"
    end

    test "when inside brackets" do
      assert {:ok, [ref, access_ref], doc} = index_references(~q{3 = foo[bar]})

      assert_reference(ref, :foo)
      assert decorate(doc, ref.range) =~ "3 = «foo»[bar]"

      assert_reference(access_ref, :bar)
      assert decorate(doc, access_ref.range) =~ "3 = foo[«bar»]"
    end

    test "when in the tail of a list" do
      assert {:ok, [ref], doc} = index_references(~q{[3 | acc]})

      assert_reference(ref, :acc)
      assert decorate(doc, ref.range) =~ "[3 | «acc»]"
    end

    test "unless it begins with underscore" do
      assert {:ok, [], _} = index_references("_")
      assert {:ok, [], _} = index_references("_unused")
      assert {:ok, [], _} = index_references("_unused = 3")
      assert {:ok, [], _} = index_references("_unused = foo()")
    end
  end
end
