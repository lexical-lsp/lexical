defmodule Lexical.RemoteControl.Build do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build.State
  alias Lexical.SourceFile

  require Logger
  use GenServer

  @tick_interval_millis 50

  # Public interface

  def schedule_compile(%Project{} = project, force? \\ false) do
    RemoteControl.call(project, GenServer, :cast, [__MODULE__, {:compile, force?}])
  end

  def compile_source_file(%Project{} = project, %SourceFile{} = source_file) do
    RemoteControl.call(project, GenServer, :cast, [__MODULE__, {:compile_file, source_file}])

    :ok
  end

  # this is for testing
  def force_compile_source_file(%Project{} = project, %SourceFile{} = source_file) do
    unless Path.absname(source_file.path) == "mix.exs" do
      RemoteControl.call(project, GenServer, :call, [
        __MODULE__,
        {:force_compile_file, source_file}
      ])
    end

    :ok
  end

  def with_lock(func) do
    RemoteControl.with_lock(__MODULE__, func)
  end

  # GenServer Callbacks
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init([]) do
    state = State.new(RemoteControl.get_project())

    with :ok <- State.set_compiler_options() do
      {:ok, state, {:continue, :initial_build}}
    end
  end

  @impl GenServer
  def handle_continue(:initial_build, %State{} = state) do
    State.initial_compile(state)
    schedule_tick()
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:force_compile_file, %SourceFile{} = source_file}, _from, %State{} = state) do
    State.compile_file(state.project, source_file)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:compile, force?}, %State{} = state) do
    State.compile_project(state, force?)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:compile_file, %SourceFile{} = source_file}, %State{} = state) do
    new_state = State.on_file_compile(state, source_file)
    {:noreply, new_state}
  end

  def handle_info(:tick, %State{} = state) do
    new_state = State.on_tick(state)
    schedule_tick()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_, %Project{} = project) do
    {:noreply, project}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_millis)
  end
end
