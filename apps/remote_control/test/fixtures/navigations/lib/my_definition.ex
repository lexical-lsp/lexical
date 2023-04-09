defmodule MyDefinition do
  @type result :: String.t()

  defmacro __using__(_opts) do
    quote do
      import MyDefinition
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
end
