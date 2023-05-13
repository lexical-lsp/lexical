defmodule Lexical.Protocol.Id do
  def next do
    [:monotonic, :positive]
    |> System.unique_integer()
    |> to_string()
  end

  def next_request_id do
    to_string(get_latest_request_id() + 1)
  end

  def put_latest_request_id(id) do
    :persistent_term.put({__MODULE__, :latest_request_id}, id)
  end

  defp get_latest_request_id do
    :persistent_term.get({__MODULE__, :latest_request_id})
  end
end
