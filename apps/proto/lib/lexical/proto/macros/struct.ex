defmodule Lexical.Proto.Macros.Struct do
  alias Lexical.Proto.Macros.Typespec

  def build(opts, env) do
    keys = Keyword.keys(opts)
    required_keys = required_keys(opts)

    keys =
      if :.. in keys do
        {splat_def, rest} = Keyword.pop(opts, :..)

        quote location: :keep do
          [
            (fn ->
               {_, _, field_name} = unquote(splat_def)
               field_name
             end).()
            | unquote(rest)
          ]
        end
      else
        keys
      end

    quote location: :keep do
      @enforce_keys unquote(required_keys)
      defstruct unquote(keys)
      @type option :: unquote(Typespec.keyword_constructor_options(opts, env))
      @type options :: [option]

      @spec new() :: t()
      @spec new(options()) :: t()
      def new(opts \\ []) do
        struct!(__MODULE__, opts)
      end

      defoverridable new: 0, new: 1
    end
  end

  defp required_keys(opts) do
    opts
    |> Enum.filter(fn
      # ignore the splat, it's always optional
      {:.., _} -> false
      # an optional signifier tuple
      {_, {:optional, _}} -> false
      # ast for an optional signifier tuple
      {_, {:optional, _, _}} -> false
      # everything else is required
      _ -> true
    end)
    |> Keyword.keys()
  end
end
