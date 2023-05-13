defmodule Lexical.Protocol.Id do
  def next do
    [:monotonic, :positive]
    |> System.unique_integer()
    |> to_string()
  end

  def next_request_id do
    latest_request_id = get_latest_request_id()

    if latest_request_id do
      to_string(latest_request_id + 1)
    end
  end

  def set_latest_request_id(id) do
    :persistent_term.put({__MODULE__, :latest_request_id}, id)
  end

  defp get_latest_request_id do
    :persistent_term.get({__MODULE__, :latest_request_id}, nil)
  end
end
