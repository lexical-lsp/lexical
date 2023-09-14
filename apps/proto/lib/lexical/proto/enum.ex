defmodule Lexical.Proto.Enum do
  alias Lexical.Proto.Macros.Typespec

  defmacro defenum(opts) do
    names =
      opts
      |> Keyword.keys()
      |> Enum.map(&{:literal, [], &1})

    value_type =
      opts
      |> Keyword.values()
      |> List.first()
      |> Macro.expand(__CALLER__)
      |> determine_type()

    name_type = Typespec.choice(names, __CALLER__)

    quote location: :keep do
      @type name :: unquote(name_type)
      @type value :: unquote(value_type)
      @type t :: name() | value()

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

  defp determine_type(i) when is_integer(i) do
    quote do
      integer()
    end
  end

  defp determine_type(s) when is_binary(s) do
    quote do
      String.t()
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
