defmodule Lexical.Server.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Lexical.Document
  alias Lexical.Server
  alias Lexical.Server.TaskQueue
  alias Lexical.Server.Transport

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      document_store_child_spec(),
      Server,
      {DynamicSupervisor, Server.Project.Supervisor.options()},
      {Task.Supervisor, name: TaskQueue.task_supervisor_name()},
      TaskQueue,
      {Transport.StdIO, [:standard_io, &Server.protocol_message/1]}
    ]

    opts = [strategy: :one_for_one, name: Server.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  def document_store_child_spec do
    {Document.Store, derive: [analysis: &Lexical.Ast.analyze/1]}
  end
end
