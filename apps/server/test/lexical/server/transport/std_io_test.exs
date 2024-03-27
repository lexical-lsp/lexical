defmodule Lexical.Server.Transport.StdIoTest do
  alias Lexical.Protocol.JsonRpc
  alias Lexical.Server.Transport.StdIO

  use ExUnit.Case

  defp request(requests) do
    {:ok, requests} =
      requests
      |> List.wrap()
      |> Enum.map_join(fn req ->
        {:ok, req} =
          req
          |> Map.put("jsonrpc", "2.0")
          |> Jason.encode!()
          |> JsonRpc.encode()

        req
      end)
      |> StringIO.open(encoding: :latin1)

    test = self()
    StdIO.start_link(requests, &send(test, {:request, &1}))
  end

  defp receive_request do
    assert_receive {:request, request}
    request
  end

  test "works with unicode characters" do
    # This tests a bug that occurred when we were using `IO.read`.
    # Due to `IO.read` reading characters, a prior request with unicode
    # in the body, can make the body length in characters longer than the content-length.
    # This would cause the prior request to consume some of the next request if they happen
    # quickly enough. If the prior request consumes the subsequent request's headers, then
    # the read for the next request will read the JSON body as headers, and will fail the
    # pattern match in the call to `parse_header`. This would cause the dreaded
    # "no match on right hand side value [...JSON content]".
    # The fix is to switch to binread, which takes bytes as an argument.
    # This series of requests is specially crafted to cause the original failure. Removing
    # a single « from the string will break the setup.
    request([
      %{method: "textDocument/doesSomething", body: "««««««««««««««««««««««"},
      %{method: "$/cancelRequest", id: 2},
      %{method: "$/cancelRequest", id: 3}
    ])

    _ = receive_request()
  end
end
