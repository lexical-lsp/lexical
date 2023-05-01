defmodule Lexical.RemoteControl.Build.ProgressServer do
  defmodule Progress do
    defstruct [:id, :kind, :title, :message, :percentage]
  end

  defmodule State do
    defstruct [
      :project,
      :label,
      :progress
    ]

    def new(project) do
      %__MODULE__{project: project}
    end
  end

  use GenServer

  def start_link(project) do
    GenServer.start_link(__MODULE__, [project])
  end

  def init(project) do
    {:ok, State.new(project)}
  end
end
