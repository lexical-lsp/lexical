defmodule Lexical.Server.Transport do
  @moduledoc """
  A behaviour for a LSP transport
  """
  @callback write(Jason.Encoder.t()) :: Jason.Encoder.t()

  alias Lexical.Server.Transport.StdIO

  @implementation Application.compile_env(:server, :transport, StdIO)

  defdelegate write(message), to: @implementation
  defdelegate write(message, opts), to: @implementation
end
