defmodule Lexical.Server.Transport.StdIO do
  alias Lexical.Protocol.Notifications.LogMessage

  alias Lexical.Protocol.JsonRpc

  @behaviour Lexical.Server.Transport

  def start_link(device, callback) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [{callback, device}])
    {:ok, pid}
  end

  def child_spec([device, callback]) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [device, callback]}}
  end

  def init({callback, device}) do
    :io.setopts([:binary, encoding: :latin1])
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
        device when device in [:stdio, :standard_io] ->
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

  def log(level, message, opts \\ [])

  def log(level, message, opts) when level in [:error, :warning, :info, :log] do
    formatted_message = format_message(message, opts)
    log_message = apply(LogMessage, level, [formatted_message])
    write(:standard_io, log_message)
    message
  end

  def log(_level, message, opts) do
    log_message = format_message(message, opts)

    write(:standard_error, log_message)
    message
  end

  # private

  defp format_message(message, opts) do
    case Keyword.get(opts, :label) do
      nil -> inspect(message) <> "\n"
      label -> "#{label}: '#{inspect(message, limit: :infinity)}\n"
    end
  end

  defp loop(buffer, device, callback) do
    case IO.read(device, :line) do
      "\n" ->
        headers = parse_headers(buffer)

        with {:ok, content_length} <-
               header_value(headers, "content-length", &String.to_integer/1),
             {:ok, data} <- read_body(device, content_length),
             {:ok, message} <- JsonRpc.decode(data) do
          callback.(message)
        end

        loop([], device, callback)

      :eof ->
        System.halt()

      line ->
        loop([line | buffer], device, callback)
    end
  end

  defp parse_headers(headers) do
    Enum.map(headers, &parse_header/1)
  end

  defp header_value(headers, header_name, converter) do
    case List.keyfind(headers, header_name, 0) do
      nil -> :error
      {_, value} -> {:ok, converter.(value)}
    end
  end

  defp read_body(device, amount) do
    case IO.read(device, amount) do
      data when is_binary(data) or is_list(data) ->
        # Ensure that incoming data is latin1 to prevent double-encoding to utf8 later
        # See https://github.com/lexical-lsp/lexical/issues/287 for context.
        data = :unicode.characters_to_binary(data, :utf8, :latin1)
        {:ok, data}

      other ->
        other
    end
  end

  defp parse_header(line) do
    [name, value] = String.split(line, ":")

    header_name =
      name
      |> String.downcase()
      |> String.trim()

    {header_name, String.trim(value)}
  end
end
