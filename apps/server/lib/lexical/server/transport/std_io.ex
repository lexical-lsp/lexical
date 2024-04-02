defmodule Lexical.Server.Transport.StdIO do
  alias Lexical.Protocol.JsonRpc

  require Logger

  @behaviour Lexical.Server.Transport

  def start_link(device, callback) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [{callback, device}])
    {:ok, pid}
  end

  def child_spec([device, callback]) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [device, callback]}}
  end

  def init({callback, device}) do
    :io.setopts(binary: true, encoding: :latin1)
    loop([], device, callback)
  end

  def write(io_device \\ :stdio, payload)

  def write(io_device, %_{} = payload) do
    with {:ok, lsp} <- Lexical.Proto.Convert.to_lsp(payload),
         {:ok, json} <- Jason.encode(lsp) do
      write(io_device, json)
    end
  end

  def write(io_device, %{} = payload) do
    with {:ok, encoded} <- Jason.encode(payload) do
      write(io_device, encoded)
    end
  end

  def write(io_device, payload) when is_binary(payload) do
    message =
      case io_device do
        device when device in [:stdio, :standard_io] or is_pid(device) ->
          {:ok, json_rpc} = JsonRpc.encode(payload)
          json_rpc

        _ ->
          payload
      end

    IO.binwrite(io_device, message)
  end

  def write(_, nil) do
  end

  def write(_, []) do
  end

  # private

  defp loop(buffer, device, callback) do
    case IO.binread(device, :line) do
      "\n" ->
        headers = parse_headers(buffer)

        with {:ok, content_length} <- content_length(headers),
             {:ok, data} <- read_body(device, content_length),
             {:ok, message} <- JsonRpc.decode(data) do
          callback.(message)
        else
          {:error, :empty_response} ->
            nil

          {:error, reason} ->
            Logger.critical("error reading protocol message: #{inspect(reason)}")
        end

        loop([], device, callback)

      :eof ->
        maybe_stop()

      line ->
        loop([line | buffer], device, callback)
    end
  end

  defp content_length(headers) do
    case List.keyfind(headers, "content-length", 0) do
      {_, len_str} ->
        {:ok, String.to_integer(len_str)}

      nil ->
        {:error, :no_content_length}
    end
  end

  defp read_body(device, byte_count) do
    case IO.binread(device, byte_count) do
      data when is_binary(data) and byte_size(data) === byte_count ->
        {:ok, data}

      data when is_binary(data) ->
        read_more(device, byte_count - byte_size(data), data)

      data when is_list(data) ->
        if Enum.count(data) === byte_count do
          {:ok, data}
        else
          remaining_bytes = byte_count - byte_size(data)
          read_more(device, remaining_bytes, data)
        end

      :eof ->
        {:error, :eof}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # give editor an extra ms if there's not enough bytes.
  defp read_more(device, byte_count, data) do
    :timer.sleep(1)

    case IO.binread(device, byte_count) do
      rest when is_binary(rest) or is_list(rest) ->
        [data | rest]

      :eof ->
        {:error, :eof}

      error ->
        error
    end
  end

  defp parse_headers(headers) do
    Enum.map(headers, &parse_header/1)
  end

  defp parse_header(line) do
    [name, value] = String.split(line, ":", parts: 2)

    header_name =
      name
      |> String.downcase()
      |> String.trim()

    {header_name, String.trim(value)}
  end

  if Mix.env() == :test do
    defp maybe_stop do
      :ok
    end
  else
    defp maybe_stop do
      System.stop()
    end
  end
end
