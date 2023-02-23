defmodule Lexical.Server.Project.Dispatch do
  defmodule State do
    alias Lexical.Project

    defstruct [:project, :registrations]

    def new(%Project{} = project) do
      %__MODULE__{project: project, registrations: %{}}
    end

    def add(%__MODULE__{} = state, message_type, pid) do
      registrations =
        Map.update(state.registrations, message_type, [pid], fn registrations ->
          [pid | registrations]
        end)

      %__MODULE__{state | registrations: registrations}
    end

    def registrations(%__MODULE__{} = state, message_type) do
      all = Map.get(state.registrations, :all, [])
      specific = Map.get(state.registrations, message_type, [])
      all ++ specific
    end

    def registered?(%__MODULE__{} = state, pid) do
      state.registrations
      |> Map.values()
      |> List.flatten()
      |> Enum.member?(pid)
    end

    def registered?(%__MODULE__{} = state, message_type, pid) do
      pid in registrations(state, message_type)
    end

    def remove(%__MODULE__{} = state, message_type, pid) do
      registrations =
        Map.update(state.registrations, message_type, [], &Enum.reject(&1, fn e -> e == pid end))

      %__MODULE__{state | registrations: registrations}
    end

    def remove_all(%__MODULE__{} = state, pid) do
      registrations =
        Map.new(state.registrations, fn {message, pids} ->
          pids = Enum.reject(pids, &(&1 == pid))
          {message, pids}
        end)

      %__MODULE__{state | registrations: registrations}
    end
  end

  alias Lexical.RemoteControl
  alias Lexical.Project
  use GenServer

  # public API

  def register(%Project{} = project, message_types) when is_list(message_types) do
    project
    |> name()
    |> GenServer.call({:register, message_types})
  end

  def registered?(%Project{} = project) do
    registered?(project, self())
  end

  def registered?(%Project{} = project, pid) when is_pid(pid) do
    project
    |> name()
    |> GenServer.call({:registered?, pid})
  end

  def broadcast(%Project{} = project, message) do
    project
    |> name()
    |> send(message)
  end

  # GenServer callbacks

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: name(project))
  end

  def child_spec(%Project{} = project) do
    %{
      id: {__MODULE__, Project.name(project)},
      start: {__MODULE__, :start_link, [project]}
    }
  end

  @impl GenServer
  def init([%Project{} = project]) do
    {:ok, _} = RemoteControl.start_link(project, self())
    {:ok, State.new(project), {:continue, :trigger_build}}
  end

  @impl GenServer
  def handle_continue(:trigger_build, %State{} = state) do
    RemoteControl.Api.schedule_compile(state.project, true)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:register, message_types}, {caller_pid, _ref}, %State{} = state) do
    Process.monitor(caller_pid)

    new_state =
      Enum.reduce(message_types, state, fn
        message_type_or_message, %State{} = state ->
          message_type = extract_message_type(message_type_or_message)
          State.add(state, message_type, caller_pid)
      end)

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:registered?, pid}, _from, %State{} = state) do
    registered? = State.registered?(state, pid)
    {:reply, registered?, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, _, pid, _}, %State{} = state) do
    new_state = State.remove_all(state, pid)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(message, %State{} = state) do
    message_type = extract_message_type(message)

    state
    |> State.registrations(message_type)
    |> Enum.each(&send(&1, message))

    {:noreply, state}
  end

  # Private api

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::dispatch"
  end

  defp extract_message_type(message_type) when is_atom(message_type), do: message_type
  defp extract_message_type(message_type) when is_tuple(message_type), do: elem(message_type, 0)
end
