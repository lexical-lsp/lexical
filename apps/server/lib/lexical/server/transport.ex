defmodule Lexical.Server.Transport do
  @moduledoc """
  A behaviour for a LSP transport
  """

  @type level :: :error | :warning | :info | :log

  @callback log(level(), Jason.Encoder.t()) :: Jason.Encoder.t()
  @callback write(Jason.Encoder.t()) :: Jason.Encoder.t()

  alias Lexical.Server.Transport.StdIO

  @implementation Application.compile_env(:server, :transport, StdIO)

  defdelegate log(level, message), to: @implementation
  defdelegate write(message), to: @implementation

  def error(message) do
    @implementation.log(:error, message)
  end
end
