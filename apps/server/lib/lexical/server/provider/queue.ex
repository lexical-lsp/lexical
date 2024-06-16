defmodule Lexical.Server.Provider.Queue do
  defmodule State do
    alias Lexical.Proto.Convert
    alias Lexical.Proto.LspTypes.ResponseError
    alias Lexical.Protocol.Requests
    alias Lexical.Server.Configuration
    alias Lexical.Server.Provider.Handlers
    alias Lexical.Server.Provider.Queue
    alias Lexical.Server.Transport
    require Logger

    defstruct ids_to_tasks: %{}, pids_to_ids: %{}

    @type t :: %__MODULE__{}

    def new do
      %__MODULE__{}
    end

    @spec add(t, Requests.request(), Configuration.t()) :: {:ok, t} | :error
    def add(%__MODULE__{} = state, request, %Configuration{} = config) do
      with {:ok, handler_module} <- Handlers.for_request(request),
           {:ok, req} <- Convert.to_native(request) do
        task = %Task{} = as_task(request, fn -> handler_module.handle(req, config) end)

        new_state = %__MODULE__{
          state
          | ids_to_tasks: Map.put(state.ids_to_tasks, request.id, task),
            pids_to_ids: Map.put(state.pids_to_ids, task.pid, request.id)
        }

        {:ok, new_state}
      else
        {:error, {:unhandled, _}} ->
          Logger.info("unhandled request #{request.method}")
          :error

        _ ->
          :error
      end
    end

    @spec cancel(t, request_id :: term()) :: t
    def cancel(%__MODULE__{} = state, request_id) do
      with {:ok, %Task{} = task} <- Map.fetch(state.ids_to_tasks, request_id),
           :ok <- Queue.cancel_task(task) do
        write_error(request_id, "Request cancelled", :request_cancelled)

        %State{
          state
          | ids_to_tasks: Map.delete(state.ids_to_tasks, request_id),
            pids_to_ids: Map.delete(state.pids_to_ids, task.pid)
        }
      else
        _ ->
          state
      end
    end

    def size(%__MODULE__{} = state) do
      map_size(state.ids_to_tasks)
    end

    def task_finished(%__MODULE__{} = state, pid, reason) do
      case Map.pop(state.pids_to_ids, pid) do
        {nil, _} ->
          state

        {request_id, new_pids_to_ids} ->
          maybe_log_task(reason, request_id)

          %__MODULE__{
            state
            | pids_to_ids: new_pids_to_ids,
              ids_to_tasks: Map.delete(state.ids_to_tasks, request_id)
          }
      end
    end

    def running?(%__MODULE__{} = state, request_id) do
      Map.has_key?(state.ids_to_tasks, request_id)
    end

    defp maybe_log_task(:normal, _),
      do: :ok

    defp maybe_log_task(reason, request_id),
      do: Logger.warning("Request id #{request_id} failed with reason #{inspect(reason)}")

    defp as_task(%{id: _} = request, func) do
      handler = fn ->
        try do
          case func.() do
            :noreply ->
              {:request_complete, request}

            {:reply, reply} ->
              write_reply(reply)

              {:request_complete, request}
          end
        rescue
          e ->
            exception_string = Exception.format(:error, e, __STACKTRACE__)
            Logger.error(exception_string)
            write_error(request.id, exception_string)

            {:request_complete, request}
        end
      end

      Queue.run_task(handler)
    end

    defp write_reply(response) do
      case Convert.to_lsp(response) do
        {:ok, lsp_response} ->
          Transport.write(lsp_response)

        error ->
          error_message = """
          Failed to convert #{response.__struct__}:

          #{inspect(error, pretty: true)}\
          """

          Logger.critical("""
          #{error_message}

          #{inspect(response, pretty: true)}\
          """)

          write_error(response.id, error_message)
      end
    end

    defp write_error(id, message, code \\ :internal_error) do
      error =
        ResponseError.new(
          code: code,
          message: message
        )

      Transport.write(%{id: id, error: error})
    end
  end

  alias Lexical.Protocol.Requests
  alias Lexical.Server.Configuration

  use GenServer

  def task_supervisor_name do
    __MODULE__.TaskSupervisor
  end

  @doc false
  def run_task(fun) when is_function(fun) do
    Task.Supervisor.async_nolink(task_supervisor_name(), fun)
  end

  @doc false
  def cancel_task(%Task{} = task) do
    Task.Supervisor.terminate_child(task_supervisor_name(), task.pid)
  end

  @spec add(Requests.request(), Configuration.t()) :: :ok
  def add(request, %Configuration{} = config) do
    GenServer.call(__MODULE__, {:add, request, config})
  end

  @spec size() :: non_neg_integer()
  def size do
    GenServer.call(__MODULE__, :size)
  end

  def cancel(%{lsp: %{id: id}}) do
    cancel(id)
  end

  def cancel(%{id: request_id}) do
    cancel(request_id)
  end

  def cancel(request_id) do
    GenServer.call(__MODULE__, {:cancel, request_id})
  end

  def running?(%{id: request_id}) do
    running?(request_id)
  end

  def running?(request_id) do
    GenServer.call(__MODULE__, {:running?, request_id})
  end

  # genserver callbacks

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, State.new()}
  end

  def handle_call({:add, request, config}, _from, %State{} = state) do
    {reply, new_state} =
      case State.add(state, request, config) do
        {:ok, new_state} -> {:ok, new_state}
        error -> {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:cancel, request_id}, _from, %State{} = state) do
    new_state = State.cancel(state, request_id)
    {:reply, :ok, new_state}
  end

  def handle_call({:running?, request_id}, _from, %State{} = state) do
    {:reply, State.running?(state, request_id), state}
  end

  def handle_call(:size, _from, %State{} = state) do
    {:reply, State.size(state), state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    new_state = State.task_finished(state, pid, reason)

    {:noreply, new_state}
  end

  def handle_info({ref, {:request_complete, _response}}, %State{} = state)
      when is_reference(ref) do
    # This head handles the replies from the tasks, which we don't really care about.
    {:noreply, state}
  end
end
