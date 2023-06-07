defmodule Lexical.Plugin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Lexical.Plugin.Supervisor,
      Lexical.Plugin.Coordinator
    ]

    opts = [strategy: :one_for_one, name: Lexical.Plugin.ApplicationSupervisor]
    Supervisor.start_link(children, opts)
  end
end
