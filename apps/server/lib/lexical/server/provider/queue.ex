defmodule Lexical.Server.Provider.Queue do
  defmodule State do
    alias Lexical.Protocol.Proto.LspTypes.ResponseError
    alias Lexical.Protocol.Requests
    alias Lexical.Server.Provider.Env
    alias Lexical.Server.Provider.Handlers
    alias Lexical.Server.Provider.Queue
    alias Lexical.Server.Transport
    require Logger

    defstruct tasks_by_id: %{}, pids_to_ids: %{}

    @type t :: %__MODULE__{}

    def new do
      %__MODULE__{}
    end

    @spec add(t, Requests.request(), Env.t()) :: {:ok, t} | :error
    def add(%__MODULE__{} = state, request, env) do
      with {:ok, handler_module} <- Handlers.for_request(request),
           {:ok, req} <- request.__struct__.to_elixir(request) do
        task = %Task{} = as_task(request, fn -> handler_module.handle(req, env) end)
        request_id = to_string(request.id)

        new_state = %__MODULE__{
          state
          | tasks_by_id: Map.put(state.tasks_by_id, request_id, task),
            pids_to_ids: Map.put(state.pids_to_ids, task.pid, request_id)
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

    @spec cancel(t, pos_integer()) :: t
    def cancel(%__MODULE__{} = state, request_id) do
      with {:ok, %Task{} = task} <- Map.fetch(state.tasks_by_id, request_id),
           true <- Process.exit(task.pid, :kill) do
        error = ResponseError.new(message: "Request cancelled", code: :request_cancelled)
        reply = %{id: request_id, error: error}
        Transport.write(reply)

        %State{
          state
          | tasks_by_id: Map.delete(state.tasks_by_id, request_id),
            pids_to_ids: Map.delete(state.pids_to_ids, task.pid)
        }
      else
        _ ->
          state
      end
    end

    def size(%__MODULE__{} = state) do
      map_size(state.tasks_by_id)
    end

    def task_finished(%__MODULE__{} = state, pid, reason) do
      case Map.pop(state.pids_to_ids, pid) do
        {nil, _} ->
          Logger.warn("Got an exit for pid #{inspect(pid)}, but it wasn't in the queue")
          state

        {request_id, new_pids_to_ids} ->
          maybe_log_task(reason, request_id)

          %__MODULE__{
            state
            | pids_to_ids: new_pids_to_ids,
              tasks_by_id: Map.delete(state.tasks_by_id, request_id)
          }
      end
    end

    def running?(%__MODULE__{} = state, request_id) do
      Map.has_key?(state.tasks_by_id, request_id)
    end

    defp maybe_log_task(:normal, _),
      do: :ok

    defp maybe_log_task(reason, %{id: request_id} = _request),
      do: maybe_log_task(reason, request_id)

    defp maybe_log_task(reason, request_id),
      do: Logger.warn("Request id #{request_id} failed with reason #{inspect(reason)}")

    defp as_task(%{id: _} = request, func) do
      handler = fn ->
        try do
          case func.() do
            :noreply ->
              {:request_complete, request}

            {:reply, reply} ->
              Transport.write(reply)
              {:request_complete, request}

            {:reply_and_alert, reply} ->
              Transport.write(reply)
              Lexical.Server.response_complete(request, reply)
              {:request_complete, request}
          end
        rescue
          e ->
            exception_string = Exception.format(:error, e, __STACKTRACE__)
            Logger.error(exception_string)

            response_error =
              ResponseError.new(
                message: exception_string,
                code: :internal_error
              )

            error = %{
              id: request.id,
              error: response_error
            }

            Transport.write(error)

            {:request_complete, request}
        end
      end

      Queue.Supervisor.run_in_task(handler)
    end
  end

  alias Lexical.Protocol.Requests
  alias Lexical.Server.Configuration
  alias Lexical.Server.Provider.Env

  use GenServer

  # public interface
  @spec add(Requests.request(), Configuration.t() | Env.t()) :: :ok
  def add(request, %Configuration{} = config) do
    env = Env.from_configuration(config)
    add(request, env)
  end

  def add(request, %Env{} = env) do
    GenServer.call(__MODULE__, {:add, request, env})
  end

  @spec size() :: non_neg_integer()
  def size do
    GenServer.call(__MODULE__, :size)
  end

  def cancel(%{id: request_id}) do
    cancel(request_id)
  end

  def cancel(request_id) when is_integer(request_id) do
    request_id
    |> Integer.to_string()
    |> cancel()
  end

  def cancel(request_id) when is_binary(request_id) do
    GenServer.call(__MODULE__, {:cancel, request_id})
  end

  def running?(%{id: request_id}) do
    running?(request_id)
  end

  def running?(request_id) when is_binary(request_id) do
    GenServer.call(__MODULE__, {:running?, request_id})
  end

  # genserver callbacks

  def child_spec do
    __MODULE__
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, State.new()}
  end

  def handle_call({:add, request, env}, _from, %State{} = state) do
    {reply, new_state} =
      case State.add(state, request, env) do
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

  # private
end
