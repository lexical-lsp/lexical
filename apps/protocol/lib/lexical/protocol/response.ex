defmodule Lexical.Protocol.Response do
  alias Lexical.Ranged
  alias Lexical.SourceFile

  def to_lsp(%_{result: result} = response) do
    case convert_to_lsp(result) do
      {:ok, converted} ->
        {:ok, Map.put(response, :result, converted)}

      error ->
        error
    end
  end

  defp fetch_source_file(%{text_document: %{uri: uri}}) do
    SourceFile.Store.fetch(uri)
  end

  defp fetch_source_file(%{source_file: %SourceFile{} = source_file}) do
    {:ok, source_file}
  end

  defp fetch_source_file(_) do
    :error
  end

  defp convert_to_lsp(%_{text_document: _} = response) do
    with {:ok, source_file} <- fetch_source_file(response) do
      convert_to_lsp(response, source_file)
    end
  end

  defp convert_to_lsp(response_list) when is_list(response_list) do
    result =
      Enum.reduce_while(response_list, [], fn response, acc ->
        case convert_to_lsp(response) do
          {:ok, converted} ->
            {:cont, [converted | acc]}

          error ->
            {:halt, error}
        end
      end)

    case result do
      l when is_list(l) ->
        {:ok, Enum.reverse(l)}

      error ->
        error
    end
  end

  defp convert_to_lsp(%_{} = response) do
    {:ok, response}
  end

  defp convert_to_lsp(other) do
    {:ok, other}
  end

  defp convert_to_lsp(%_struct{} = response, %SourceFile{} = source_file) do
    case Ranged.Lsp.impl_for(response) do
      nil ->
        key_value_pairs =
          response
          |> Map.from_struct()
          |> Enum.reduce(response, fn {key, value}, response ->
            {:ok, value} = convert_to_lsp(value, source_file)
            Map.put(response, key, value)
          end)

        {:ok, Map.merge(response, key_value_pairs)}

      _impl ->
        Ranged.Lsp.from_native(response, source_file)
    end
  end

  defp convert_to_lsp(not_a_struct, %SourceFile{}) do
    {:ok, not_a_struct}
  end
end
