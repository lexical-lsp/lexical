defmodule Lexical.Server.Project.Intelligence do
  defmodule State do
    alias Lexical.Format
    alias Lexical.Project
    defstruct project: nil, struct_modules: MapSet.new()

    def new(%Project{} = project) do
      %__MODULE__{project: project}
    end

    def delete_struct_module(%__MODULE__{} = state, module_name) do
      module_path = module_path(module_name)

      struct_modules = MapSet.delete(state.struct_modules, module_path)
      %__MODULE__{state | struct_modules: struct_modules}
    end

    def add_struct_module(%__MODULE__{} = state, module_name) do
      module_path = module_path(module_name)
      %__MODULE__{state | struct_modules: MapSet.put(state.struct_modules, module_path)}
    end

    def child_defines_struct?(%__MODULE__{} = state, prefix) do
      module_path = module_path(prefix)
      Enum.any?(state.struct_modules, &paths_match?(module_path, &1))
    end

    def child_struct_modules(%__MODULE__{} = state, prefix) do
      module_path = module_path(prefix)

      for struct_path <- state.struct_modules,
          paths_match?(module_path, struct_path) do
        Enum.join(struct_path, ".")
      end
    end

    def defines_struct?(%__MODULE__{} = state, module_name) do
      module_path = module_path(module_name)
      Enum.any?(state.struct_modules, &(&1 == module_path))
    end

    defp module_path(module_name) do
      module_name
      |> Format.module()
      |> String.split(".")
    end

    defp paths_match?([], [_]) do
      true
    end

    defp paths_match?([], _) do
      false
    end

    defp paths_match?([same | haystack], [same | needle]) do
      paths_match?(haystack, needle)
    end

    defp paths_match?(_, _) do
      false
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

  def child_struct_modules(%Project{} = project, parent_module) do
    project
    |> name()
    |> GenServer.call({:child_struct_modules, parent_module})
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
  def handle_call({:child_struct_modules, parent_module}, _from, %State{} = state) do
    {:reply, State.child_struct_modules(state, parent_module), state}
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
