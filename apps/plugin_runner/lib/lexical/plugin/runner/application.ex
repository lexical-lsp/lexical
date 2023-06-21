defmodule Lexical.Plugin.Runner.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Lexical.Plugin.Runner
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Runner.Supervisor,
      Runner.Coordinator
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lexical.Plugin.Runner.Application.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
