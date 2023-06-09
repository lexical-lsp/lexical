defmodule Lexical.Server.Project.Intelligence do
  defmodule State do
    alias Lexical.Formats
    alias Lexical.Project
    defstruct project: nil, struct_modules: MapSet.new()

    def new(%Project{} = project) do
      discover_existing_structs(%__MODULE__{project: project})
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

    def descendent_defines_struct?(%__MODULE__{} = state, prefix, %Range{} = range) do
      module_path = module_path(prefix)
      Enum.any?(state.struct_modules, &prefixes_match?(module_path, &1, range))
    end

    def descendent_struct_modules(%__MODULE__{} = state, prefix, %Range{} = range) do
      module_path = module_path(prefix)

      for struct_path <- state.struct_modules,
          prefixes_match?(module_path, struct_path, range) do
        Enum.join(struct_path, ".")
      end
    end

    defp module_path(module_name) do
      module_name
      |> Formats.module()
      |> String.split(".")
    end

    defp prefixes_match?([], remainder, %Range{} = range) do
      length(remainder) in range
    end

    defp prefixes_match?([same | haystack], [same | needle], range) do
      prefixes_match?(haystack, needle, range)
    end

    defp prefixes_match?(_, _, _) do
      false
    end

    require Logger

    defp discover_existing_structs(%__MODULE__{} = state) do
      # This might be a performance / memory issue on larger projects. It
      # iterates through all modules, loading each as necessary and then removing them
      # if they're not already loaded to try and claw back some memory

      for {module_name_charlist, _, loaded?} <- :code.all_available(),
          elixir_module?(module_name_charlist),
          module_name = List.to_atom(module_name_charlist),
          Code.ensure_loaded(module_name),
          is_list(module_name.__info__(:struct)),
          reduce: state do
        state ->
          new_state = add_struct_module(state, module_name)

          unless loaded? do
            :code.delete(module_name)
            :code.purge(module_name)
          end

          new_state
      end
    end

    defp elixir_module?(module_name_charlist) do
      List.starts_with?(module_name_charlist, 'Elixir.')
    end
  end

  alias Lexical.Project
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.Project.Dispatch

  use GenServer
  import Api.Messages

  @generations [
                 :self,
                 :child,
                 :grandchild,
                 :great_grandchild,
                 :great_great_grandchild,
                 :great_great_great_grandchild
               ]
               |> Enum.with_index()
               |> Map.new()

  @type generation_name ::
          :self
          | :child
          | :grandchild
          | :great_grandchild
          | :great_great_grandchild
          | :great_great_great_grandchild

  @type module_spec :: module() | String.t()
  @type module_name :: String.t()
  @type generation_spec :: generation_name | non_neg_integer
  @type generation_option :: {:from, generation_spec} | {:to, generation_spec}
  @type generation_options :: [generation_option]

  # Public api
  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: name(project))
  end

  @doc """
  Collects struct modules in the given ranges

  When given your project, and a root module, this function returns a list of module names
  that fall within the given collection range. Given a module's descendent tree, a
  range can be specified in the following ways:

  `named:`  A keyword list contiaining `:from` (optional, defaults to `:self`) and
   `:to` (optional, defaults to `:self`) keys. The values of these keys can be either
   a number representing the degree of the  descendent generation (o for self, 1
   for child, etc) or named generations (`:self`, `:child`, `:grandchild`, etc). For example,
   the collectionn range: `from: :child, to: :great_grandchild` will collect all struct
   modules where the  root module is thier parent up to and including all modules where the
   root module is their great grandparent, and is equivalent to the range `1..2`.

  `range`: A `Range` struct containing the starting and ending generations. The module passed in
  as `root_module` is generation 0, its child is generation 1, its grandchild is generation 2,
  and so on.
  """
  @spec collect_struct_modules(Project.t(), module_spec) :: [module_name]
  @spec collect_struct_modules(Project.t(), module_spec, generation_options | Range.t()) :: [
          module_name
        ]
  def collect_struct_modules(project, root_module, opts \\ [])

  def collect_struct_modules(%Project{} = project, root_module, opts) when is_list(opts) do
    collect_struct_modules(project, root_module, extract_range(opts))
  end

  def collect_struct_modules(%Project{} = project, root_module, %Range{} = range) do
    project
    |> name()
    |> GenServer.call({:collect_struct_modules, root_module, range})
  end

  @doc """
  Returns true if a module in the given generation range defines a struct

  see `collect_struct_modules/3` for an explanation of generation ranges
  """

  @spec defines_struct?(Project.t(), module_spec) :: boolean
  @spec defines_struct?(Project.t(), module_spec, generation_options | Range.t()) :: boolean
  def defines_struct?(project, root_module, opts \\ [])

  def defines_struct?(%Project{} = project, root_module, opts) when is_list(opts) do
    defines_struct?(project, root_module, extract_range(opts))
  end

  def defines_struct?(%Project{} = project, root_module, %Range{} = range) do
    project
    |> name()
    |> GenServer.call({:defines_struct?, root_module, range})
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
  def handle_call({:defines_struct?, parent_module, %Range{} = range}, _from, %State{} = state) do
    {:reply, State.descendent_defines_struct?(state, parent_module, range), state}
  end

  @impl GenServer
  def handle_call(
        {:collect_struct_modules, parent_module, %Range{} = range},
        _from,
        %State{} = state
      ) do
    {:reply, State.descendent_struct_modules(state, parent_module, range), state}
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

  defp extract_range(opts) when is_list(opts) do
    from = Keyword.get(opts, :from, :self)
    from = Map.get(@generations, from, from)

    to = Keyword.get(opts, :to, :self)
    to = Map.get(@generations, to, to)

    from..to
  end
end
