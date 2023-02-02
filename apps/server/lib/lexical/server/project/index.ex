defmodule Lexical.Server.Project.Index do
  alias Lexical.Project
  use GenServer

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: :"#{Project.name(project)}::index")
  end

  def init([%Project{} = project]) do
    {:ok, project}
  end
end
