defmodule Lexical.Proto.Decoders do
  alias Lexical.Proto.CompileMetadata
  alias Lexical.Proto.Typespecs

  defmacro for_notifications(_) do
    notification_modules = CompileMetadata.notification_modules()
    notification_matchers = Enum.map(notification_modules, &build_notification_matcher_macro/1)
    notification_decoders = Enum.map(notification_modules, &build_notifications_decoder/1)

    quote do
      defmacro notification(method) do
        quote do
          %{"method" => unquote(method), "jsonrpc" => "2.0"}
        end
      end

      defmacro notification(method, params) do
        quote do
          %{"method" => unquote(method), "params" => unquote(params), "jsonrpc" => "2.0"}
        end
      end

      use Typespecs, for: :notifications

      unquote_splicing(notification_matchers)

      @spec decode(String.t(), map()) :: {:ok, notification} | {:error, any}
      unquote_splicing(notification_decoders)

      def decode(method, _) do
        {:error, {:unknown_notification, method}}
      end

      def __meta__(:events) do
        unquote(notification_modules)
      end

      def __meta__(:notifications) do
        unquote(notification_modules)
      end
    end
  end

  defmacro for_requests(_) do
    request_modules = CompileMetadata.request_modules()
    request_matchers = Enum.map(request_modules, &build_request_matcher_macro/1)
    request_decoders = Enum.map(request_modules, &build_request_decoder/1)

    quote do
      def __meta__(:requests) do
        unquote(request_modules)
      end

      defmacro request(id, method) do
        quote do
          %{"method" => unquote(method), "id" => unquote(id), "jsonrpc" => "2.0"}
        end
      end

      defmacro request(id, method, params) do
        quote do
          %{"method" => unquote(method), "id" => unquote(id), "params" => unquote(params)}
        end
      end

      use Typespecs, for: :requests

      unquote_splicing(request_matchers)

      @spec decode(String.t(), map()) :: {:ok, request} | {:error, any}
      unquote_splicing(request_decoders)

      def decode(method, _) do
        {:error, {:unknown_request, method}}
      end
    end
  end

  defp build_notification_matcher_macro(notification_module) do
    macro_name = module_to_macro_name(notification_module)
    method_name = notification_module.__meta__(:method_name)

    quote do
      defmacro unquote(macro_name)() do
        method_name = unquote(method_name)

        quote do
          %{"method" => unquote(method_name), "jsonrpc" => "2.0"}
        end
      end
    end
  end

  defp build_notifications_decoder(notification_module) do
    method_name = notification_module.__meta__(:method_name)

    quote do
      def decode(unquote(method_name), request) do
        unquote(notification_module).parse(request)
      end
    end
  end

  defp build_request_matcher_macro(notification_module) do
    macro_name = module_to_macro_name(notification_module)
    method_name = notification_module.__meta__(:method_name)

    quote do
      defmacro unquote(macro_name)(id) do
        method_name = unquote(method_name)

        quote do
          %{"method" => unquote(method_name), "id" => unquote(id), "jsonrpc" => "2.0"}
        end
      end
    end
  end

  defp build_request_decoder(request_module) do
    method_name = request_module.__meta__(:method_name)

    quote do
      def decode(unquote(method_name), request) do
        unquote(request_module).parse(request)
      end
    end
  end

  defp module_to_macro_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
