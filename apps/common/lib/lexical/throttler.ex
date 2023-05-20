defmodule Lexical.Throttler do
  defmodule JobInfo do
    defstruct [:type, :job_func, :interval, :timer_ref]

    def new(job_func, type, interval) when is_function(job_func, 0) do
      %__MODULE__{type: type, job_func: job_func, interval: interval}
    end

    def new(%__MODULE__{} = job_info, timer_ref) do
      %{job_info | timer_ref: timer_ref}
    end
  end

  defmodule State do
    defstruct job_infos: %{}

    def ready_for_next?(%__MODULE__{} = state, %JobInfo{type: type}) do
      previous_timer_ref = get_in(state, [Access.key(:job_infos), type, Access.key(:timer_ref)])
      is_nil(previous_timer_ref) or Process.read_timer(previous_timer_ref) == false
    end

    def job_func_by_type(%__MODULE__{} = state, type) do
      state.job_infos |> Map.get(type) |> Map.get(:job_func)
    end
  end

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def run(%JobInfo{} = job_info) do
    GenServer.cast(__MODULE__, {:run, job_info})
  end

  def init(_) do
    {:ok, %State{}}
  end

  def handle_cast({:run, %{type: type} = job_info}, state) do
    state =
      if State.ready_for_next?(state, job_info) do
        timer_ref = Process.send_after(self(), {:job, type}, job_info.interval)
        job_info = JobInfo.new(job_info, timer_ref)
        %{state | job_infos: Map.put(state.job_infos, type, job_info)}
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:job, type}, state) do
    job_func = State.job_func_by_type(state, type)
    job_func.()
    {:noreply, state}
  end
end
