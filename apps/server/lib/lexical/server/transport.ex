defmodule Lexical.Server.Transport do
  @moduledoc """
  A behaviour for a LSP transport
  """

  @type level :: :error | :warning | :info | :log

  @callback log(level(), Jason.Encoder.t()) :: Jason.Encoder.t()
  @callback write(Jason.Encoder.t()) :: Jason.Encoder.t()

  alias Lexical.Server.Transport.StdIO

  defdelegate log(level, message), to: StdIO
  defdelegate write(message), to: StdIO

  def error(message) do
    StdIO.log(:error, message)
  end
end
