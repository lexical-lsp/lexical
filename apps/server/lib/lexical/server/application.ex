defmodule Lexical.Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Lexical.Server.Provider
  alias Lexical.Server.Transport
  use Application

  @impl true
  def start(_type, _args) do
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
end
