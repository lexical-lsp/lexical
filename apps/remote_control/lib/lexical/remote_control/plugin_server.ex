defmodule Lexical.RemoteControl.PluginServer do
  alias Lexical.Enhancement
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages

  import Messages

  use GenServer

  def run(%Enhancement{} = enhancement) do
    # GenServer.cast(__MODULE__, {:run, enhancement})
    GenServer.call(__MODULE__, {:run, enhancement})
  end

  # Public
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:run, %{validate: [m, f, a], enhance: thing} = enhancement}, _from, state) do
    # def handle_cast({:run, %{validate: validate, enhance: enhance} = enhancement}, state) do
    if apply(m, f, a) do
      publish(thing, enhancement)
      # enhance.() |> publish(enhancement)
    else
      :ok
    end

    # {:noreply, state}
    {:reply, :ok, state}
  end

  defp publish(enhance_result, enhancement) do
    %{project: project, uri: uri, type: type, source: source} = enhancement
    result = List.wrap(enhance_result)

    if type == :file do
      diagnostics =
        file_diagnostics(project: project, uri: uri, diagnostics: result, source: source)

      RemoteControl.notify_listener(diagnostics)
    else
      diagnostics = project_diagnostics(project: project, diagnostics: result, source: source)
      RemoteControl.notify_listener(diagnostics)
    end
  end
end
