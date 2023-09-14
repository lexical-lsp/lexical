defmodule Lexical.Proto.Macros.Message do
  alias Lexical.Document

  alias Lexical.Proto.Macros.{
    Access,
    Meta,
    Parse,
    Struct,
    Typespec
  }

  def build(meta_type, method, types, param_names, env, opts \\ []) do
    parse_fn =
      if Keyword.get(opts, :include_parse?, true) do
        Parse.build(types)
      end

    quote do
      unquote(Struct.build(types, env))
      unquote(Access.build())
      unquote(parse_fn)
      unquote(Meta.build(types))

      @type t :: unquote(Typespec.t())

      def method do
        unquote(method)
      end

      def __meta__(:method_name) do
        unquote(method)
      end

      def __meta__(:type) do
        unquote(meta_type)
      end

      def __meta__(:param_names) do
        unquote(param_names)
      end
    end
  end

  def generate_elixir_types(caller_module, message_types) do
    message_types
    |> Enum.reduce(message_types, fn
      {:text_document, _}, types ->
        Keyword.put(types, :document, quote(do: Document))

      {:position, _}, types ->
        Keyword.put(types, :position, quote(do: Document.Position))

      {:range, _}, types ->
        Keyword.put(types, :range, quote(do: Document.Range))

      _, types ->
        types
    end)
    |> Keyword.put(:lsp, quote(do: unquote(caller_module).LSP))
  end
end
