defmodule Lexical.Common.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Lexical.Module

  @impl true
  def start(_type, _args) do
    children = [Module.Loader]

    opts = [strategy: :one_for_one, name: Common.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
