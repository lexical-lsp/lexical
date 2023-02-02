defmodule Lexical.Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Lexical.Provider
  alias Lexical.Transport
  use Application

  @impl true
  def start(_type, _args) do
    # on_start()
    add_jsonrpc_backend()

    children = [
      Lexical.SourceFile.Store,
      Lexical.Server,
      {DynamicSupervisor, name: Lexical.Server.Project.Supervisor.dynamic_supervisor_name()},
      Provider.Queue.Supervisor.child_spec(),
      Provider.Queue.child_spec(),
      {Lexical.Server.IOServer, [:standard_io, &Lexical.Server.protocol_message/1]}
    ]

    opts = [strategy: :one_for_one, name: Lexical.Server.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp on_start do
    # Transport.StdIO.setup()
    # Transport.StdIO.listen()
  end

  defp add_jsonrpc_backend() do
    Application.put_env(:logger, :backends, [Lexical.JsonRpc.Backend])

    Application.put_env(:logger, Lexical.JsonRpc.Backend,
      level: :debug,
      format: "$message",
      metadata: []
    )

    {:ok, _} = Logger.add_backend(Lexical.JsonRpc.Backend)
    :ok = Logger.remove_backend(:console, flush: true)
  end
end
