defmodule Lexical.Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Lexical.Provider
  alias Lexical.Server.JsonRpc.Backend, as: JsonRpcBackend
  alias Lexical.Server.Transport
  use Application

  @impl true
  def start(_type, _args) do
    add_jsonrpc_backend()

    children = [
      Lexical.SourceFile.Store,
      Lexical.Server,
      {DynamicSupervisor, name: Lexical.Server.Project.Supervisor.dynamic_supervisor_name()},
      Provider.Queue.Supervisor.child_spec(),
      Provider.Queue.child_spec(),
      {Transport.StdIO, [:standard_io, &Lexical.Server.protocol_message/1]}
    ]

    opts = [strategy: :one_for_one, name: Lexical.Server.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp add_jsonrpc_backend() do
    Application.put_env(:logger, :backends, [JsonRpcBackend])

    Application.put_env(:logger, JsonRpcBackend,
      level: :debug,
      format: "$message",
      metadata: []
    )

    {:ok, _} = Logger.add_backend(JsonRpcBackend)
    :ok = Logger.remove_backend(:console, flush: true)
  end
end
