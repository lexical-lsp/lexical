defmodule MyDefinition do
  @type result :: String.t()

  @spec greet(String.t()) :: result
  def greet(name) do
    "Hello, #{name}!"
  end
end
