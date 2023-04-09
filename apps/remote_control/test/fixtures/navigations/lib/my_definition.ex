defmodule MyDefinition do
  @type result :: String.t()

  defmacro __using__(_opts) do
    quote do
      import MyDefinition

      def hello_func_in_using() do
        "Hello, world!"
      end
    end
  end

  @spec greet(String.t()) :: result
  def greet(name) do
    "Hello, #{name}!"
  end

  defmacro print_hello do
    quote do
      IO.puts("Hello, world!")
    end
  end

  def uses_greet() do
    greet("world")
  end

  def uses_print_hello_macro() do
    print_hello()
  end

  @b 2

  def uses_variable_and_attr() do
    a = 1

    if a == 1 do
      a
    else
      @b
    end
  end

  def uses_elixir_std_module() do
    String.to_integer("123")
  end

  def uses_erlang_module() do
    :erlang.binary_to_atom("hello", :utf8)
  end
end
