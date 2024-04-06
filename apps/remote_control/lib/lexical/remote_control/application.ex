defmodule Lexical.RemoteControl.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias Lexical.RemoteControl

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      if RemoteControl.project_node?() do
        [
          {RemoteControl.Commands.Reindex, nil},
          RemoteControl.Commands.Rename,
          RemoteControl.Module.Loader,
          {RemoteControl.Dispatch, progress: true},
          RemoteControl.ModuleMappings,
          RemoteControl.Build,
          RemoteControl.Build.CaptureServer,
          RemoteControl.Plugin.Runner.Supervisor,
          RemoteControl.Plugin.Runner.Coordinator,
          RemoteControl.Search.Store.Backends.Ets,
          {RemoteControl.Search.Store,
           [
             &RemoteControl.Search.Indexer.create_index/1,
             &RemoteControl.Search.Indexer.update_index/2
           ]}
        ]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    children = Enum.reject(children, &is_nil/1)
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lexical.RemoteControl.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
