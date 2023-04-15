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
end
