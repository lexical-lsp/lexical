defmodule Lexical.Proto.Notification do
  alias Lexical.Proto.CompileMetadata
  alias Lexical.Proto.Macros.Message

  defmacro defnotification(method) do
    do_defnotification(method, [], __CALLER__)
  end

  defmacro defnotification(method, params_module_ast) do
    params_module =
      params_module_ast
      |> Macro.expand(__CALLER__)
      |> Code.ensure_compiled!()

    types = params_module.__meta__(:raw_types)
    do_defnotification(method, types, __CALLER__)
  end

  defp do_defnotification(method, types, caller) do
    CompileMetadata.add_notification_module(caller.module)

    jsonrpc_types = [
      jsonrpc: quote(do: literal("2.0")),
      method: quote(do: literal(unquote(method)))
    ]

    param_names = Keyword.keys(types)
    lsp_types = Keyword.merge(jsonrpc_types, types)
    elixir_types = Message.generate_elixir_types(caller.module, lsp_types)
    lsp_module_name = Module.concat(caller.module, LSP)

    quote location: :keep do
      defmodule LSP do
        unquote(Message.build({:notification, :lsp}, method, lsp_types, param_names, caller))

        def new(opts \\ []) do
          opts
          |> Keyword.merge(method: unquote(method), jsonrpc: "2.0")
          |> super()
        end
      end

      unquote(
        Message.build({:notification, :elixir}, method, elixir_types, param_names, caller,
          include_parse?: false
        )
      )

      unquote(build_parse(method))

      def new(opts \\ []) do
        opts = Keyword.merge(opts, method: unquote(method), jsonrpc: "2.0")

        # use struct here because initially, the non-lsp struct doesn't have
        # to be filled out. Calling to_elixir fills it out.
        struct(__MODULE__, lsp: LSP.new(opts), method: unquote(method), jsonrpc: "2.0")
      end

      defimpl Jason.Encoder, for: unquote(caller.module) do
        def encode(notification, opts) do
          Jason.Encoder.encode(notification.lsp, opts)
        end
      end

      defimpl Jason.Encoder, for: unquote(lsp_module_name) do
        def encode(notification, opts) do
          %{
            jsonrpc: "2.0",
            method: unquote(method),
            params: Map.take(notification, unquote(param_names))
          }
          |> Jason.Encode.map(opts)
        end
      end
    end
  end

  defp build_parse(method) do
    quote do
      def parse(%{"method" => unquote(method), "jsonrpc" => "2.0"} = request) do
        params = Map.get(request, "params") || %{}
        flattened_notificaiton = Map.merge(request, params)

        case LSP.parse(flattened_notificaiton) do
          {:ok, raw_lsp} ->
            struct_opts = [method: unquote(method), jsonrpc: "2.0", lsp: raw_lsp]
            notification = struct(__MODULE__, struct_opts)
            {:ok, notification}

          error ->
            error
        end
      end
    end
  end
end
