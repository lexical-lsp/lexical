defmodule Lexical.Server.Project.SearchListener do
  alias Lexical.Formats
  alias Lexical.Project
  alias Lexical.Protocol.Id
  alias Lexical.Protocol.Requests
  alias Lexical.RemoteControl.Api
  alias Lexical.Server
  alias Lexical.Server.Window

  import Api.Messages

  use GenServer
  require Logger

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: name(project))
  end

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::search_listener"
  end

  @impl GenServer
  def init([%Project{} = project]) do
    Api.register_listener(project, self(), [
      project_reindex_requested(),
      project_reindexed()
    ])

    {:ok, project}
  end

  @impl GenServer
  def handle_info(project_reindex_requested(), %Project{} = project) do
    Logger.info("project reindex requested")
    send_code_lens_refresh()

    {:noreply, project}
  end

  def handle_info(project_reindexed(elapsed_ms: elapsed), %Project{} = project) do
    message = "Reindexed #{Project.name(project)} in #{Formats.time(elapsed, unit: :millisecond)}"
    Logger.info(message)
    send_code_lens_refresh()

    Window.show_info_message(message)

    {:noreply, project}
  end

  defp send_code_lens_refresh do
    request = Requests.CodeLensRefresh.new(id: Id.next())
    Server.server_request(request)
  end
end
