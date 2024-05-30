defmodule Lexical.RemoteControl.Build do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build.Document.Compilers.HEEx
  alias Lexical.RemoteControl.Build.State
  alias Lexical.VM.Versions

  require Logger
  use GenServer

  @tick_interval_millis 50

  # Public interface

  def path(%Project{} = project) do
    %{elixir: elixir, erlang: erlang} = Versions.current()
    erlang_major = erlang |> String.split(".") |> List.first()
    elixir_version = Version.parse!(elixir)
    elixir_major = "#{elixir_version.major}.#{elixir_version.minor}"
    build_root = Project.build_path(project)
    Path.join([build_root, "erl-#{erlang_major}", "elixir-#{elixir_major}"])
  end

  def schedule_compile(%Project{} = _project, force? \\ false) do
    GenServer.cast(__MODULE__, {:compile, force?})
  end

  def compile_document(%Project{} = _project, %Document{} = document) do
    with false <- Path.absname(document.path) == "mix.exs",
         false <- HEEx.recognizes?(document) do
      GenServer.cast(__MODULE__, {:compile_file, document})
    end

    :ok
  end

  # this is for testing
  def force_compile_document(%Document{} = document) do
    with false <- Path.absname(document.path) == "mix.exs",
         false <- HEEx.recognizes?(document) do
      GenServer.call(__MODULE__, {:force_compile_file, document})
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
      {:ok, state, {:continue, :ensure_build_directory}}
    end
  end

  @impl GenServer
  def handle_continue(:ensure_build_directory, %State{} = state) do
    State.ensure_build_directory(state)
    schedule_tick()
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:force_compile_file, %Document{} = document}, _from, %State{} = state) do
    State.compile_file(state, document)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:compile, force?}, %State{} = state) do
    State.compile_project(state, force?)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:compile_file, %Document{} = document}, %State{} = state) do
    new_state = State.on_file_compile(state, document)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:tick, %State{} = state) do
    new_state = State.on_tick(state)
    schedule_tick()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(msg, %Project{} = project) do
    Logger.warning("Undefined message: #{inspect(msg)}")
    {:noreply, project}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_millis)
  end
end
