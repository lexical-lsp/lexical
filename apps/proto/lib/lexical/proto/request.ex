defmodule Lexical.Proto.Request do
  alias Lexical.Proto.CompileMetadata
  alias Lexical.Proto.Macros.Message
  alias Lexical.Proto.TypeFunctions

  import TypeFunctions, only: [optional: 1, literal: 1]

  defmacro defrequest(method) do
    do_defrequest(method, [], __CALLER__)
  end

  defmacro defrequest(method, params_module_ast) do
    types = fetch_types(params_module_ast, __CALLER__)
    do_defrequest(method, types, __CALLER__)
  end

  defmacro server_request(method, params_module_ast, response_module_ast) do
    types = fetch_types(params_module_ast, __CALLER__)

    quote do
      unquote(do_defrequest(method, types, __CALLER__))

      def parse_response(response) do
        unquote(response_module_ast).parse(response)
      end
    end
  end

  defmacro server_request(method, response_module_ast) do
    quote do
      unquote(do_defrequest(method, [], __CALLER__))

      def parse_response(response) do
        unquote(response_module_ast).parse(response)
      end
    end
  end

  defp fetch_types(params_module_ast, env) do
    params_module =
      params_module_ast
      |> Macro.expand(env)
      |> Code.ensure_compiled!()

    params_module.__meta__(:raw_types)
  end

  defp do_defrequest(method, types, caller) do
    CompileMetadata.add_request_module(caller.module)
    # id is optional so we can resuse the parse function. If it's required,
    # it will go in the pattern match for the params, which won't work.

    jsonrpc_types = [
      id: quote(do: optional(one_of([string(), integer()]))),
      jsonrpc: quote(do: literal("2.0")),
      method: quote(do: literal(unquote(method)))
    ]

    lsp_types = Keyword.merge(jsonrpc_types, types)
    elixir_types = Message.generate_elixir_types(caller.module, lsp_types)
    param_names = Keyword.keys(types)
    lsp_module_name = Module.concat(caller.module, LSP)

    Message.build({:request, :elixir}, method, elixir_types, param_names, caller,
      include_parse?: false
    )

    quote location: :keep do
      defmodule LSP do
        unquote(Message.build({:request, :lsp}, method, lsp_types, param_names, caller))

        def new(opts \\ []) do
          opts
          |> Keyword.merge(method: unquote(method), jsonrpc: "2.0")
          |> super()
        end
      end

      alias Lexical.Proto.Convert
      alias Lexical.Protocol.Types

      unquote(
        Message.build({:request, :elixir}, method, elixir_types, param_names, caller,
          include_parse?: false
        )
      )

      unquote(build_parse(method))

      def new(opts \\ []) do
        opts = Keyword.merge(opts, method: unquote(method), jsonrpc: "2.0")

        raw = LSP.new(opts)
        # use struct here because initially, the non-lsp struct doesn't have
        # to be filled out. Calling to_elixir fills it out.
        struct(__MODULE__, lsp: raw, id: raw.id, method: unquote(method), jsonrpc: "2.0")
      end

      defimpl Jason.Encoder, for: unquote(caller.module) do
        def encode(request, opts) do
          Jason.Encoder.encode(request.lsp, opts)
        end
      end

      defimpl Jason.Encoder, for: unquote(lsp_module_name) do
        def encode(request, opts) do
          params =
            case Map.take(request, unquote(param_names)) do
              empty when map_size(empty) == 0 -> nil
              params -> params
            end

          %{
            id: request.id,
            jsonrpc: "2.0",
            method: unquote(method),
            params: params
          }
          |> Jason.Encode.map(opts)
        end
      end
    end
  end

  defp build_parse(method) do
    quote do
      def parse(%{"method" => unquote(method), "id" => id, "jsonrpc" => "2.0"} = request) do
        params = Map.get(request, "params") || %{}
        flattened_request = Map.merge(request, params)

        case LSP.parse(flattened_request) do
          {:ok, raw_lsp} ->
            struct_opts = [id: id, method: unquote(method), jsonrpc: "2.0", lsp: raw_lsp]
            request = struct(__MODULE__, struct_opts)
            {:ok, request}

          error ->
            error
        end
      end
    end
  end
end
