defmodule Lexical.Proto.Response do
  alias Lexical.Proto.CompileMetadata

  alias Lexical.Proto.Macros.{
    Access,
    Meta,
    Struct,
    Typespec
  }

  defmacro defresponse(response_type) do
    CompileMetadata.add_response_module(__CALLER__.module)

    jsonrpc_types = [
      id: quote(do: optional(one_of([integer(), string()]))),
      error: quote(do: optional(Lexical.Proto.LspTypes.ResponseError)),
      result: quote(do: optional(unquote(response_type)))
    ]

    quote location: :keep do
      alias Lexical.Proto.LspTypes
      unquote(Access.build())
      unquote(Struct.build(jsonrpc_types, __CALLER__))
      unquote(Typespec.t())
      unquote(Meta.build(jsonrpc_types))

      unquote(constructors())

      defimpl Jason.Encoder, for: unquote(__CALLER__.module) do
        def encode(%_{error: nil} = response, opts) do
          %{
            jsonrpc: "2.0",
            id: response.id,
            result: response.result
          }
          |> Jason.Encode.map(opts)
        end

        def encode(response, opts) do
          %{
            jsonrpc: "2.0",
            id: response.id,
            error: response.error
          }
          |> Jason.Encode.map(opts)
        end
      end
    end
  end

  defp constructors do
    quote do
      def new(id, result) do
        struct(__MODULE__, result: result, id: id)
      end

      def error(id, error_code) when is_integer(error_code) do
        %__MODULE__{id: id, error: LspTypes.ResponseError.new(code: error_code)}
      end

      def error(id, error_code) when is_atom(error_code) do
        %__MODULE__{id: id, error: LspTypes.ResponseError.new(code: error_code)}
      end

      def error(id, error_code, error_message)
          when is_integer(error_code) and is_binary(error_message) do
        %__MODULE__{
          id: id,
          error: LspTypes.ResponseError.new(code: error_code, message: error_message)
        }
      end

      def error(id, error_code, error_message)
          when is_atom(error_code) and is_binary(error_message) do
        %__MODULE__{
          id: id,
          error: LspTypes.ResponseError.new(code: error_code, message: error_message)
        }
      end
    end
  end
end
