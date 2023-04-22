defmodule Lexical.RemoteControl.ProjectNode do
  alias Lexical.RemoteControl

  defmodule State do
    defstruct [:project, :paths, :cookie, boot_timeout: 5_000]

    def new(project) do
      paths = format_prepending_paths(RemoteControl.glob_paths())
      cookie = Node.get_cookie()

      struct!(__MODULE__, paths: paths, cookie: cookie, project: project)
    end

    defp format_prepending_paths(paths_as_charlists) do
      Enum.map_join(paths_as_charlists, " -pa ", &Path.expand/1)
    end
  end

  use GenServer

  def start_link(project) do
    state = State.new(project)
    GenServer.start_link(__MODULE__, state, [])
  end

  def init(state) do
    {:ok, state, {:continue, :start_remote_control}}
  end

  def handle_continue(:start_remote_control, state) do
    name = RemoteControl.node_name(state.project)
    {:ok, elixir_executable} = RemoteControl.elixir_executable(state.project)

    cmd =
      "#{elixir_executable} --name #{name} -pa #{state.paths} --cookie #{state.cookie} --no-halt -e 'Node.connect(#{inspect(Node.self())})'"

    case System.shell(cmd) do
      {_, 0} ->
        {:noreply, state}

      _ ->
        {:stop, :boot_failed, state}
    end
  end
end
