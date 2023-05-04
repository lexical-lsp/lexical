defmodule Lexical.Server.Project.Progress do
  require Logger
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Types.WorkDone
  alias Lexical.Server.Transport

  defmodule Value do
    defstruct [:title, :message, :percentage]

    def new(options) do
      %__MODULE__{
        title: options[:title],
        message: options[:message],
        percentage: options[:percentage]
      }
    end
  end

  defmodule State do
    defstruct [
      :project,
      :token_by_label,
      :percentages_by_label,
      :progress
    ]

    def new(project) do
      %__MODULE__{
        project: project,
        progress: nil,
        token_by_label: %{},
        percentages_by_label: %{}
      }
    end

    def add(state, label, message \\ "") do
      # Only need to care about `begin` and `report` events
      # `end` event is too simple

      case kind(label) do
        "prepare" ->
          percentages =
            Map.put(state.percentages_by_label, trim(label), %{
              percentage: 0,
              total: message,
              finished: %{}
            })

          %{state | percentages_by_label: percentages}

        "begin" ->
          token = System.unique_integer([:positive])
          progress = Value.new(title: trim(label))

          %{
            state
            | token_by_label: Map.put(state.token_by_label, trim(label), token),
              progress: progress
          }

        _ ->
          # TODO: refactor and reduce complexity
          percentages_by_label = percentages(state, label, message)
          state = %{state | percentages_by_label: percentages_by_label}
          progress = report_progress(state, label, message)
          %{state | progress: progress}
      end
    end

    defp percentages(state, "compile", file) do
      Logger.info("compile state: #{inspect(state)}")

      total = state.percentages_by_label["compile"].total
      finished = state.percentages_by_label["compile"].finished
      finished? = Map.has_key?(finished, file)

      if not finished? do
        finished = Map.put(finished, file, true)

        %{
          "compile" => %{
            total: total,
            finished: finished,
            percentage: trunc(map_size(finished) * 100 / total)
          }
        }
      else
        state.percentages_by_label
      end
    end

    defp percentages(state, _, _) do
      state.percentages_by_label
    end

    defp report_progress(state, label, message) do
      case trim(label) do
        "compile" ->
          compile_report_progress(state, message)

        _ ->
          Value.new(message: message)
      end
    end

    defp compile_report_progress(state, message) do
      case state.percentages_by_label["compile"] do
        nil ->
          nil

        _ ->
          Value.new(
            message: message,
            percentage: state.percentages_by_label["compile"].percentage
          )
      end
    end

    def trim(label) do
      label
      |> String.trim_trailing(".prepare")
      |> String.trim_trailing(".begin")
      |> String.trim_trailing(".end")
    end

    def kind(label) do
      kind = String.split(label, ".") |> List.last()
      if kind in ["prepare", "begin", "end"], do: kind, else: "report"
    end

    def create_workdone_progress(%__MODULE__{} = state, label) do
      token = get_token(state, label)
      progress = Notifications.CreateWorkDoneProgress.new(token: token)
      Transport.write(progress)
    end

    def begin_progress(%__MODULE__{} = state, label) do
      token = get_token(state, label)
      value = to_progress_begin(state)
      progress = Notifications.Progress.new(token: token, value: value)
      Transport.write(progress)
    end

    def report_progress(%__MODULE__{} = state, label) do
      token = get_token(state, label)
      value = to_progress_report(state)

      if token && value do
        progress = Notifications.Progress.new(token: token, value: value)
        Transport.write(progress)
      end
    end

    def end_progress(%__MODULE__{} = state, label) do
      token = get_token(state, label)
      value = WorkDone.Progress.End.new(kind: "end")
      progress = Notifications.Progress.new(token: token, value: value)
      Transport.write(progress)
    end

    defp to_progress_begin(%__MODULE__{progress: progress}) do
      WorkDone.Progress.Begin.new(kind: "begin", title: progress.title)
    end

    defp to_progress_report(%__MODULE__{progress: nil}) do
      # NOTE: we need to use nil to ignore prepare progress
      # and some incorrect progress like `compile` without percentage
      nil
    end

    defp to_progress_report(%__MODULE__{progress: progress}) do
      WorkDone.Progress.Report.new(
        kind: "report",
        message: progress.message,
        percentage: progress.percentage
      )
    end

    defp get_token(%__MODULE__{} = state, label) do
      Map.get(state.token_by_label, State.trim(label))
    end
  end

  alias Lexical.Project
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.Server.Project.Dispatch

  require Logger

  import Messages

  use GenServer

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: name(project))
  end

  def child_spec(%Project{} = project) do
    %{
      id: {__MODULE__, Project.name(project)},
      start: {__MODULE__, :start_link, [project]}
    }
  end

  # GenServer callbacks

  @impl GenServer
  def init([project]) do
    Dispatch.register(project, [project_progress()])
    {:ok, State.new(project)}
  end

  @impl true
  def handle_info(project_progress(label: label, message: message), %State{} = state) do
    Logger.info("label is #{label}, message is #{message}")
    state = State.add(state, label, message)

    case State.kind(label) do
      "begin" ->
        State.create_workdone_progress(state, label)
        State.begin_progress(state, label)

      "end" ->
        State.end_progress(state, label)

      _ ->
        State.report_progress(state, label)
    end

    {:noreply, state}
  end

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::progress"
  end
end
