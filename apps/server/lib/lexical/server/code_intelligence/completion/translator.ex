defmodule Lexical.Server.CodeIntelligence.Completion.Translator do
  alias Lexical.Protocol.Types.Completion

  defmacro __using__(for: what_to_translate) do
    caller_module = __CALLER__.module

    protocol_implementations =
      what_to_translate
      |> List.wrap()
      |> Enum.map(fn translated_module ->
        protocol_implementation(caller_module, translated_module)
      end)

    quote location: :keep do
      import unquote(__MODULE__),
        only: [
          boost: 1,
          boost: 2,
          fallback: 2,
          plain_text: 1,
          plain_text: 2,
          snippet: 1,
          snippet: 2
        ]

      def translate(thing, _env) do
        :skip
      end

      defoverridable translate: 2

      unquote_splicing(protocol_implementations)
    end
  end

  def snippet(snippet_text, options \\ []) do
    options
    |> Keyword.put(:insert_text, snippet_text)
    |> Keyword.put(:insert_text_format, :snippet)
    |> Completion.Item.new()
  end

  def plain_text(insert_text, options \\ []) do
    options
    |> Keyword.put(:insert_text, insert_text)
    |> Completion.Item.new()
  end

  def fallback(nil, fallback), do: fallback
  def fallback("", fallback), do: fallback
  def fallback(detail, _), do: detail

  def boost(text, amount \\ 5)

  def boost(text, amount) when amount in 0..10 do
    boost_char = ?* - amount
    IO.iodata_to_binary([boost_char, text])
  end

  def boost(text, _) do
    boost(text, 0)
  end

  defp protocol_implementation(caller_module, translated_module) do
    quote do
      defimpl Lexical.Completion.Translatable, for: unquote(translated_module) do
        def translate(item, env) do
          unquote(caller_module).translate(item, env)
        end
      end
    end
  end
end
