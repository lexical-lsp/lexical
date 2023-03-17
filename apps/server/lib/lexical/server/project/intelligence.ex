defmodule Lexical.Server.Project.Intelligence do
  defmodule State do
    alias Lexical.Format
    alias Lexical.Project

    defstruct project: nil, struct_modules: MapSet.new()

    def new(%Project{} = project) do
      %__MODULE__{project: project}
    end

    def delete_struct_module(%__MODULE__{} = state, module_name) do
      string_name = Format.module(module_name)

      %__MODULE__{state | struct_modules: MapSet.delete(state.struct_modules, string_name)}
    end

    def add_struct_module(%__MODULE__{} = state, module_name) do
      string_name = Format.module(module_name)

      %__MODULE__{state | struct_modules: MapSet.put(state.struct_modules, string_name)}
    end

    def child_defines_struct?(%__MODULE__{} = state, prefix) do
      Enum.any?(state.struct_modules, &String.starts_with?(&1, prefix))
    end

    def defines_struct?(%__MODULE__{} = state, module_name) do
      Enum.any?(state.struct_modules, &(&1 == module_name))
    end
  end

  alias Lexical.Project
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.Project.Dispatch

  use GenServer
  import Api.Messages

  # Public api
  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: name(project))
  end

  def defines_struct?(%Project{} = project, module_or_name) do
    project
    |> name()
    |> GenServer.call({:defines_struct?, module_or_name})
  end

  def child_defines_struct?(%Project{} = project, parent_module) do
    project
    |> name()
    |> GenServer.call({:child_defines_struct?, parent_module})
  end

  def child_spec(%Project{} = project) do
    %{
      id: {__MODULE__, Project.name(project)},
      start: {__MODULE__, :start_link, [project]}
    }
  end

  # GenServer callbacks

  @impl GenServer
  def init([%Project{} = project]) do
    Dispatch.register(project, [module_updated()])
    state = State.new(project)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:child_defines_struct?, parent_module}, _from, %State{} = state) do
    {:reply, State.child_defines_struct?(state, parent_module), state}
  end

  @impl GenServer
  def handle_call({:defines_struct?, parent_module}, _from, %State{} = state) do
    {:reply, State.defines_struct?(state, parent_module), state}
  end

  @impl GenServer
  def handle_info(module_updated(name: module_name, struct: nil), %State{} = state) do
    state = State.delete_struct_module(state, module_name)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(module_updated(name: module_name), %State{} = state) do
    state = State.add_struct_module(state, module_name)
    {:noreply, state}
  end

  # Private

  def name(%Project{} = project) do
    :"#{Project.name(project)}::intelligence"
  end
end
