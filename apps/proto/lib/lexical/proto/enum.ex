defmodule Lexical.Proto.Enum do
  defmacro defenum(opts) do
    quote location: :keep do
      unquote(parse_functions(opts))

      def parse(unknown) do
        {:error, {:invalid_constant, unknown}}
      end

      unquote_splicing(encoders(opts))

      def encode(val) do
        {:error, {:invalid_value, __MODULE__, val}}
      end

      unquote_splicing(enum_macros(opts))

      def __meta__(:types) do
        {:constant, __MODULE__}
      end

      def __meta__(:type) do
        :enum
      end
    end
  end

  defp parse_functions(opts) do
    for {name, value} <- opts do
      quote location: :keep do
        def parse(unquote(value)) do
          {:ok, unquote(name)}
        end
      end
    end
  end

  defp enum_macros(opts) do
    for {name, value} <- opts do
      quote location: :keep do
        defmacro unquote(name)() do
          unquote(value)
        end
      end
    end
  end

  defp encoders(opts) do
    for {name, value} <- opts do
      quote location: :keep do
        def encode(unquote(name)) do
          {:ok, unquote(value)}
        end
      end
    end
  end
end
