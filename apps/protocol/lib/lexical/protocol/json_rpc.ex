defmodule Lexical.Protocol.JsonRpc do
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Requests

  @crlf "\r\n"

  def decode(message_string) do
    with {:ok, json_map} <- Jason.decode(message_string) do
      do_decode(json_map)
    end
  end

  def encode(%_proto_module{} = proto_struct) do
    with {:ok, encoded} <- Jason.encode(proto_struct) do
      encode(encoded)
    end
  end

  def encode(payload) when is_binary(payload) or is_list(payload) do
    content_length = IO.iodata_length(payload)

    json_rpc = [
      "Content-Length: ",
      to_string(content_length),
      @crlf,
      @crlf,
      payload
    ]

    {:ok, json_rpc}
  end

  defp do_decode(%{"id" => _id, "result" => nil}) do
    :error
  end

  defp do_decode(%{"method" => method, "id" => _id} = request) do
    Requests.decode(method, request)
  end

  defp do_decode(%{"method" => method} = notification) do
    Notifications.decode(method, notification)
  end
end
