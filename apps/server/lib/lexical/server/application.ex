defmodule Lexical.Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Lexical.Document
  alias Lexical.Server
  alias Lexical.Server.Project
  alias Lexical.Server.Provider
  alias Lexical.Server.Transport

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Document.Store, derive: [analysis: &Lexical.Ast.analyze/1]},
      Server,
      {DynamicSupervisor, Project.Supervisor.options()},
      Provider.Queue.Supervisor.child_spec(),
      Provider.Queue.child_spec(),
      {Transport.StdIO, [:standard_io, &Server.protocol_message/1]}
    ]

    opts = [strategy: :one_for_one, name: Server.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
