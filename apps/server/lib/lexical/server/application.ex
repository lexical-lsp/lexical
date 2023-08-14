defmodule Lexical.Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Lexical.Server.Provider
  alias Lexical.Server.Transport
  alias Lexical.VM.Versions

  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    check_version()

    children = [
      Lexical.Document.Store,
      Lexical.Server,
      {DynamicSupervisor, Lexical.Server.Project.Supervisor.options()},
      Provider.Queue.Supervisor.child_spec(),
      Provider.Queue.child_spec(),
      {Transport.StdIO, [:standard_io, &Lexical.Server.protocol_message/1]}
    ]

    opts = [strategy: :one_for_one, name: Lexical.Server.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp check_version do
    unless Versions.compatible?() do
      {:ok, compiled_versions} = Versions.compiled()

      compiled_versions = Versions.to_versions(compiled_versions)
      current_versions = Versions.current() |> Versions.to_versions()

      compiled_erlang = compiled_versions.erlang
      current_erlang = current_versions.erlang

      message = """
      Lexical failed its version check. This is a FATAL Error!
      Lexical is running on Erlang #{current_erlang} and the compiled files were built on
      Erlang #{compiled_erlang}.

      If you wish to run Lexical under Erlang version #{current_erlang}, you must rebuild lexical
      under an Erlang version that is <= #{current_erlang.major}.

      Detected Lexical running on erlang #{current_erlang.major} and needs >= #{compiled_erlang.major}
      """

      Logger.emergency(message)
      # Wait for the logs to flush
      Process.sleep(500)
      System.halt()
    end
  end
end
