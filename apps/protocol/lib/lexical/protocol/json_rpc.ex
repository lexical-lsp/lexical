defmodule Lexical.Protocol.JsonRpc do
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Notifications

  def decode(message_string) do
    with {:ok, json_map} <- Jason.decode(message_string) do
      do_decode(json_map)
    end
  end

  def encode(message) do
    Jason.encode(message)
  end

  defp do_decode(%{"method" => method, "id" => id} = request) do
    Requests.decode(method, request)
  end

  defp do_decode(%{"method" => method} = notification) do
    Notifications.decode(method, notification)
  end
end
