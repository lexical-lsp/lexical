defmodule Lexical.Proto do
  alias Lexical.Proto.Decoders

  defmacro __using__([]) do
    quote location: :keep do
      alias Lexical.Proto
      alias Lexical.Proto.LspTypes

      import Lexical.Proto.TypeFunctions
      import Proto.Alias, only: [defalias: 1]
      import Proto.Enum, only: [defenum: 1]
      import Proto.Notification, only: [defnotification: 1, defnotification: 2]

      import Proto.Request,
        only: [defrequest: 1, defrequest: 2, server_request: 2, server_request: 3]

      import Proto.Response, only: [defresponse: 1]
      import Proto.Type, only: [deftype: 1]
    end
  end

  defmacro __using__(opts) when is_list(opts) do
    function_name =
      case Keyword.get(opts, :decoders) do
        :notifications ->
          :for_notifications

        :requests ->
          :for_requests

        _ ->
          invalid_decoder!(__CALLER__)
      end

    quote do
      @before_compile {Decoders, unquote(function_name)}
    end
  end

  defmacro __using__(_) do
    invalid_decoder!(__CALLER__)
  end

  defp invalid_decoder!(caller) do
    raise CompileError.exception(
            description: "Invalid decoder type. Must be either :notifications or :requests",
            file: caller.file,
            line: caller.line
          )
  end
end
