defmodule Project.Macros do
  defmacro macro_add(a, b) do
    quote do
      unquote(a) + unquote(b)
    end
  end

  defmacro l(message) do
    quote do
      require Logger
      Logger.info("message is: #{unquote(inspect(message))}")
    end
  end
end
